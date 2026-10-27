import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/sdb/sdb_key.dart';
import 'package:galaxy_wristore/core/sdb/sdb_session.dart';

import '../support/fake_sdbd.dart';

Matcher _fails(WatchError error, [Pattern? message]) => throwsA(
  isA<WatchException>()
      .having((e) => e.error, 'error', error)
      .having((e) => e.message, 'message', message == null ? anything : contains(message)),
);

Stream<List<int>> _bytes(List<int> bytes) => Stream.value(bytes);

void main() {
  late SdbKey key;
  setUpAll(() => key = SdbKey.generate());

  Future<FakeSdbd> watch({int maxData = 262144}) async {
    final watch = await FakeSdbd.start(maxData: maxData);
    addTearDown(watch.close);
    return watch;
  }

  Future<SdbSession> connect(
    FakeSdbd watch, {
    SdbOptions options = const SdbOptions(readTimeout: Duration(seconds: 5), approvalTimeout: Duration(seconds: 5)),
    void Function()? onApprovalNeeded,
  }) async {
    final session = await SdbSession.connect(
      host: '127.0.0.1',
      port: watch.port,
      key: key,
      keyName: 'phone@test',
      options: options,
      onApprovalNeeded: onApprovalNeeded,
    );
    addTearDown(session.close);
    return session;
  }

  test('a new key is confirmed once and then remembered', () async {
    final fake = await watch();
    var asked = 0;
    expect((await connect(fake, onApprovalNeeded: () => asked++)).banner, 'device::SM-R800::0');
    expect(fake.confirmations, 1);
    expect(asked, 1);
    expect(fake.keyNames, ['phone@test']);
    expect((await connect(fake, onApprovalNeeded: () => asked++)).banner, 'device::SM-R800::0');
    expect(fake.confirmations, 1);
    expect(asked, 1);
  });

  test('a denied key ends without approval', () async {
    final fake = await watch()
      ..allowNewKeys = false;
    await expectLater(connect(fake), _fails(WatchError.approvalTimeout));
  });

  test('a key nobody confirms times out', () async {
    final fake = await watch()
      ..confirmDelay = const Duration(seconds: 3);
    final options = SdbOptions(
      readTimeout: const Duration(seconds: 5),
      approvalTimeout: const Duration(milliseconds: 300),
    );
    await expectLater(connect(fake, options: options), _fails(WatchError.approvalTimeout));
  });

  test('giving up while the watch asks drops that connection at once, and a new one asks again', () async {
    final fake = await watch()
      ..confirmDelay = const Duration(seconds: 3);
    final giveUp = Completer<void>();
    var asked = 0;
    final started = DateTime.now();
    final first = SdbSession.connect(
      host: '127.0.0.1',
      port: fake.port,
      key: key,
      keyName: 'phone@test',
      options: const SdbOptions(readTimeout: Duration(seconds: 5), approvalTimeout: Duration(seconds: 5)),
      onApprovalNeeded: () {
        asked++;
        giveUp.complete();
      },
      giveUp: giveUp.future,
    );
    await expectLater(first, _fails(WatchError.approvalTimeout));
    expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 2)));
    expect(asked, 1);

    // Once the watch is showing its question for the dropped connection, a new connection makes it ask again.
    while (fake.confirmations < 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fake.confirmDelay = Duration.zero;
    final second = await connect(fake, onApprovalNeeded: () => asked++);
    expect(second.banner, 'device::SM-R800::0');
    expect(fake.confirmations, 2);
    expect(asked, 2);
  });

  test('a watch that closes at once is busy, one that resets the connection too', () async {
    final fake = await watch()
      ..busy = true;
    await expectLater(connect(fake), _fails(WatchError.busy));
    fake.busyReset = true;
    await expectLater(connect(fake), _fails(WatchError.busy));
  });

  test('an address that refuses the connection is unreachable', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    await expectLater(
      SdbSession.connect(host: '127.0.0.1', port: port, key: key, keyName: 'phone@test'),
      _fails(WatchError.unreachable),
    );
  });

  test('a watch that accepts but never answers is not answering', () async {
    final fake = await watch()
      ..silent = true;
    const options = SdbOptions(helloTimeout: Duration(milliseconds: 300));
    await expectLater(connect(fake, options: options), _fails(WatchError.notAnswering));
  });

  test('something that is not sdb is a protocol error', () async {
    final fake = await watch()
      ..sendGarbage = true;
    await expectLater(connect(fake), _fails(WatchError.protocol));
  });

  test('a watch that announces packets too small to carry a file is a protocol error', () async {
    for (final maxData in [8, 1023]) {
      await expectLater(connect(await watch(maxData: maxData)), _fails(WatchError.protocol, 'too small'));
    }
  });

  test('shell returns the output and reports whole lines as they arrive', () async {
    final fake = await watch()
      ..shells['pkgcmd -l'] = 'first line\r\nsecond line\nПривет, last without newline'
      ..shellChunk = 7;
    final session = await connect(fake);
    final lines = <String>[];
    final all = await session.shell('pkgcmd -l', onLine: lines.add);
    expect(all, 'first line\r\nsecond line\nПривет, last without newline');
    expect(lines, ['first line', 'second line', 'Привет, last without newline']);
  });

  test('an empty command output is an empty string', () async {
    expect(await (await connect(await watch())).shell('true'), '');
  });

  test('a command printing too much is refused, and the session goes on', () async {
    final fake = await watch()
      ..shells['cat big'] = 'x' * ((4 << 20) + 10)
      ..shells['echo ok'] = 'ok\n';
    final session = await connect(fake);
    await expectLater(session.shell('cat big'), _fails(WatchError.protocol, 'too much'));
    expect(await session.shell('echo ok'), 'ok\n');
  });

  test('calls made at the same time run one after another', () async {
    final fake = await watch()
      ..shells['a'] = 'A' * 5000
      ..shells['b'] = 'B' * 5000
      ..shellChunk = 100;
    final session = await connect(fake);
    final results = await Future.wait([session.shell('a'), session.shell('b'), session.shell('a')]);
    expect(results, ['A' * 5000, 'B' * 5000, 'A' * 5000]);
  });

  test('push sends a file in chunks the watch accepts and reports progress', () async {
    final fake = await watch(maxData: 4096);
    final data = Uint8List.fromList(List.generate(50000, (i) => i * 31));
    final session = await connect(fake);
    final progress = <int>[];
    await session.push(
      '/home/owner/share/tmp/sdk_tools/a.wgt',
      Stream.fromIterable([data.sublist(0, 30000), data.sublist(30000)]),
      onProgress: progress.add,
    );
    expect(progress.last, data.length);
    expect(progress, List.of(progress)..sort());
    expect(fake.files['/home/owner/share/tmp/sdk_tools/a.wgt'], data);
    expect(fake.modes['/home/owner/share/tmp/sdk_tools/a.wgt'], 420);
    expect(fake.writeSizes.every((size) => size <= 4096), isTrue, reason: 'no write larger than the watch\'s maxdata');
  });

  test('an empty file is pushed too', () async {
    final fake = await watch();
    await (await connect(fake)).push('/tmp/empty.bin', _bytes(const []));
    expect(fake.files['/tmp/empty.bin'], isEmpty);
  });

  test('a closed service that sends again does not confuse the next call', () async {
    final fake = await watch()
      ..staleClose = true
      ..shells['echo ok'] = 'ok\n';
    final session = await connect(fake);
    await session.push('/tmp/x.bin', _bytes(Uint8List(10)));
    expect(await session.shell('echo ok'), 'ok\n');
    expect(await session.shell('echo ok'), 'ok\n');
  });

  test('remote paths with odd characters are refused before anything is sent', () async {
    final fake = await watch();
    final session = await connect(fake);
    for (final path in ['relative.bin', '/tmp/a b', '/tmp/a,0644', '/tmp/a;rm', '/tmp/\u0000', '', '/']) {
      await expectLater(session.push(path, _bytes(const [1])), _fails(WatchError.refused), reason: path);
    }
    expect(fake.files, isEmpty);
  });

  test('pull reads a file whose frames the packets cut anywhere', () async {
    const path = '/opt/usr/home/owner/media/Music/Over the Horizon.mp3';
    final data = Uint8List.fromList(List.generate(30000, (i) => i * 7));
    final fake = await watch()
      ..files[path] = data
      ..shells['echo ok'] = 'ok\n';
    final session = await connect(fake);
    final received = BytesBuilder();
    final progress = <int>[];
    expect(await session.pull(path, received.add, onProgress: progress.add), data.length);
    expect(received.takeBytes(), data);
    expect(progress.last, data.length);
    // What the finished transfer still sends does not confuse the next call
    expect(await session.shell('echo ok'), 'ok\n');
  });

  test('pull of a missing file fails with the watch\'s reason, a larger one than allowed is refused', () async {
    const path = '/opt/usr/home/owner/media/big.mp3';
    final fake = await watch()
      ..files[path] = Uint8List(20000)
      ..shells['echo ok'] = 'ok\n';
    final session = await connect(fake);
    await expectLater(
      session.pull('/opt/usr/home/owner/media/none.mp3', (_) {}),
      _fails(WatchError.refused, 'No such file'),
    );
    await expectLater(session.pull(path, (_) {}, maxBytes: 10000), _fails(WatchError.refused, 'larger than 10000'));
    expect(await session.shell('echo ok'), 'ok\n');
  });

  test('upload takes a media name with spaces, the installer\'s push still does not', () async {
    final fake = await watch();
    const path = '/opt/usr/home/owner/media/Music/Over the Horizon.mp3';
    final session = await connect(fake);
    await session.upload(path, _bytes(Uint8List(10)));
    await expectLater(session.push(path, _bytes(const [1])), _fails(WatchError.refused));
    for (final bad in ['relative.bin', '/a/../b', '/tmp/\u0000', '/dir/', '']) {
      await expectLater(session.upload(bad, _bytes(const [1])), _fails(WatchError.refused), reason: bad);
      await expectLater(session.pull(bad, (_) {}), _fails(WatchError.refused), reason: bad);
    }
    // A send request ends the path at its last comma, so an upload refuses one; a read has no such field
    await expectLater(session.upload('/tmp/a,0644', _bytes(const [1])), _fails(WatchError.refused));
    expect(fake.files[path]!.length, 10);
  });

  test('a file the watch will not take is refused with its reason', () async {
    const path = '/opt/usr/home/owner/media/full.mp3';
    final fake = await watch()
      ..refuseUploads.add(path)
      ..shells['echo ok'] = 'ok\n';
    final session = await connect(fake);
    await expectLater(session.upload(path, _bytes(Uint8List(100))), _fails(WatchError.refused, 'No space left'));
    expect(await session.shell('echo ok'), 'ok\n');
  });

  test('data that cannot be read ends the transfer without a file, and the session goes on', () async {
    final fake = await watch()
      ..shells['echo ok'] = 'ok\n';
    final session = await connect(fake);
    final failing = Stream<List<int>>.fromIterable([Uint8List(10)])
        .asyncMap((chunk) => throw const FileSystemException('gone'));
    await expectLater(session.upload('/tmp/x.bin', failing), throwsA(isA<FileSystemException>()));
    expect(fake.files.containsKey('/tmp/x.bin'), isFalse);
    expect(await session.shell('echo ok'), 'ok\n');
  });

  test('a call on a closed session fails as lost', () async {
    final session = await connect(await watch());
    await session.close();
    await expectLater(session.shell('x'), _fails(WatchError.lost));
  });
}
