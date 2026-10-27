import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/sdb/watch_scanner.dart';

import '../support/fake_sdbd.dart';

class _FakeProbe implements SdbProbe {
  _FakeProbe(this.answers, {this.delay = Duration.zero});

  final Map<String, ProbeResult> answers;
  final Duration delay;
  final List<Duration> waits = [];
  int running = 0;
  int peak = 0;

  @override
  Future<ProbeResult> probe(String host, Duration timeout) async {
    waits.add(timeout);
    peak = ++running > peak ? running : peak;
    await Future<void>.delayed(delay);
    running--;
    return answers[host] ?? ProbeResult.none;
  }
}

List<String> _hosts(String own, int prefix) => [
  for (final address in WatchScanner.candidates(own, prefix)) address.host,
];

void main() {
  test('a /24 network gives its 253 other hosts', () {
    final list = _hosts('192.168.0.223', 24);
    expect(list, hasLength(253));
    expect(list.first, '192.168.0.1');
    expect(list.last, '192.168.0.254');
    expect(list, isNot(contains('192.168.0.223')));
  });

  test('small networks are scanned whole', () {
    expect(_hosts('192.168.43.1', 30), ['192.168.43.2']);
    expect(_hosts('10.1.2.4', 29), ['10.1.2.1', '10.1.2.2', '10.1.2.3', '10.1.2.5', '10.1.2.6']);
    // A /22 has 1021 other hosts; the six that end in .0 or .255 are not watch addresses
    expect(_hosts('10.0.0.5', 22), hasLength(1015));
  });

  test('a larger network is cut down to the /24 around the phone', () {
    for (final prefix in [21, 16, 8]) {
      final list = _hosts('10.20.30.40', prefix);
      expect(list, hasLength(253), reason: 'prefix $prefix');
      expect(list.every((host) => host.startsWith('10.20.30.')), isTrue);
    }
  });

  test('addresses that are not private and nonsense prefixes give nothing', () {
    for (final own in ['8.8.8.8', '100.64.1.1', '127.0.0.1', '::1', 'watch.local']) {
      expect(_hosts(own, 24), isEmpty, reason: own);
    }
    for (final prefix in [-1, 0, 31, 32, 33]) {
      expect(_hosts('192.168.0.5', prefix), isEmpty, reason: 'prefix $prefix');
    }
    expect(_hosts('172.16.5.9', 24), hasLength(253));
    expect(_hosts('172.32.5.9', 24), isEmpty);
  });

  test('subnet masks give prefix lengths', () {
    expect(WatchScanner.prefixLengthOf('255.255.255.0'), 24);
    expect(WatchScanner.prefixLengthOf('255.255.252.0'), 22);
    expect(WatchScanner.prefixLengthOf('255.255.255.252'), 30);
    expect(WatchScanner.prefixLengthOf(' 255.0.0.0 '), 8);
    for (final mask in ['255.0.255.0', '255.255.255', '255.255.255.256', 'mask', '0.0.0.x']) {
      expect(WatchScanner.prefixLengthOf(mask), isNull, reason: mask);
    }
  });

  List<WatchAddress> all() => WatchScanner.candidates('192.168.0.223', 24);

  test('scan returns the sdb devices in address order, busy ones marked', () async {
    final probe = _FakeProbe({
      '192.168.0.188': ProbeResult.sdb,
      '192.168.0.9': ProbeResult.sdbBusy,
      '192.168.0.50': ProbeResult.other,
    });
    final progress = <double>[];
    final found = await WatchScanner(probe: probe).scan(all(), onProgress: progress.add);
    expect(found.map((watch) => watch.address.host), ['192.168.0.9', '192.168.0.188']);
    expect(found.map((watch) => watch.busy), [true, false]);
    expect(progress.last, 1);
    expect(progress, List.of(progress)..sort());
  });

  test('a second, patient pass runs only when the first found nothing', () async {
    final nothing = _FakeProbe({});
    expect(await WatchScanner(probe: nothing).scan(all()), isEmpty);
    expect(nothing.waits.toSet(), {WatchScanner.firstPassTimeout, WatchScanner.secondPassTimeout});
    expect(nothing.waits, hasLength(253 * 2));

    final quick = _FakeProbe({'192.168.0.188': ProbeResult.sdb});
    await WatchScanner(probe: quick).scan(all());
    expect(quick.waits.toSet(), {WatchScanner.firstPassTimeout});
  });

  test('no more probes run at once than allowed', () async {
    final probe = _FakeProbe({}, delay: const Duration(milliseconds: 2));
    await WatchScanner(probe: probe, parallelism: 8).scan(all());
    expect(probe.peak, inInclusiveRange(2, 8));
  });

  test('an empty candidate list scans nothing', () async {
    expect(await WatchScanner(probe: _FakeProbe({})).scan(const []), isEmpty);
  });

  group('the real probe on loopback', () {
    late FakeSdbd watch;
    setUp(() async => watch = await FakeSdbd.start());
    tearDown(() => watch.close());

    Future<ProbeResult> probe({Duration timeout = const Duration(milliseconds: 500)}) =>
        TcpSdbProbe(port: watch.port).probe('127.0.0.1', timeout);

    test('recognizes an sdb daemon by its authorization request, without asking for approval', () async {
      expect(await probe(), ProbeResult.sdb);
      expect(watch.confirmations, 0);
    });

    test('a daemon that closes or resets at once is busy', () async {
      watch.busy = true;
      expect(await probe(), ProbeResult.sdbBusy);
      watch.busyReset = true;
      expect(await probe(), ProbeResult.sdbBusy);
    });

    test('some other service is not an sdb daemon, and a silent one does not hang the scan', () async {
      watch.sendGarbage = true;
      expect(await probe(), ProbeResult.other);
      watch
        ..sendGarbage = false
        ..silent = true;
      final started = DateTime.now();
      expect(await probe(timeout: const Duration(milliseconds: 300)), ProbeResult.other);
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 3)));
    });

    test('an HTTP server is not an sdb daemon', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) async {
        socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
        await socket.close();
      });
      expect(
        await TcpSdbProbe(port: server.port).probe('127.0.0.1', const Duration(milliseconds: 500)),
        ProbeResult.other,
      );
    });

    test('a closed port is nothing', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      expect(await TcpSdbProbe(port: port).probe('127.0.0.1', const Duration(milliseconds: 300)), ProbeResult.none);
    });
  });
}
