import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/sdb/network_watch_finder.dart';
import 'package:galaxy_wristore/core/sdb/watch_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Wi-Fi details as a device tells them: an address and mask, nothing, or an error.
class _Info implements NetworkInfo {
  _Info({this.ip, this.mask, this.fails = false});

  final String? ip;
  final String? mask;
  final bool fails;

  @override
  Future<String?> getWifiIP() async => fails ? throw Exception('no Wi-Fi details here') : ip;

  @override
  Future<String?> getWifiSubmask() async => mask;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers as a watch at [watch] and records every host it was asked about.
class _Probe implements SdbProbe {
  _Probe(this.watch);

  final String watch;
  final Set<String> asked = {};

  @override
  Future<ProbeResult> probe(String host, Duration timeout) async {
    asked.add(host);
    return host == watch ? ProbeResult.sdb : ProbeResult.none;
  }
}

void main() {
  test('a device on Wi-Fi searches its Wi-Fi network', () async {
    final probe = _Probe('192.168.1.40');
    var askedForAddresses = false;
    final finder = NetworkWatchFinder(
      info: _Info(ip: '192.168.1.7', mask: '255.255.255.0'),
      scanner: WatchScanner(probe: probe),
      localAddresses: () async {
        askedForAddresses = true;
        return ['10.0.0.2'];
      },
    );

    final found = await finder.find();

    expect([for (final w in found) w.address.host], ['192.168.1.40']);
    expect(probe.asked, hasLength(253));
    expect(askedForAddresses, isFalse);
  });

  test('a computer without Wi-Fi details searches the networks of its connections, at most two', () async {
    final probe = _Probe('10.0.0.9');
    final finder = NetworkWatchFinder(
      info: _Info(),
      scanner: WatchScanner(probe: probe),
      localAddresses: () async => ['192.168.1.7', '10.0.0.2', '172.16.5.5'],
    );

    final found = await finder.find();

    expect([for (final w in found) w.address.host], ['10.0.0.9']);
    expect(probe.asked, contains('192.168.1.200'));
    expect(probe.asked, contains('10.0.0.200'));
    expect(probe.asked.where((h) => h.startsWith('172.16.')), isEmpty);
    expect(probe.asked, isNot(contains('192.168.1.7')));
  });

  test('Wi-Fi details that cannot be read fall back to the connections', () async {
    final probe = _Probe('192.168.0.30');
    final finder = NetworkWatchFinder(
      info: _Info(fails: true),
      scanner: WatchScanner(probe: probe),
      localAddresses: () async => ['192.168.0.12'],
    );

    expect([for (final w in await finder.find()) w.address.host], ['192.168.0.30']);
  });

  test('without a private address, nothing is searched', () async {
    final probe = _Probe('192.168.0.30');
    final finder = NetworkWatchFinder(
      info: _Info(ip: '100.72.10.4'),
      scanner: WatchScanner(probe: probe),
      localAddresses: () async => const [],
    );

    expect(await finder.find(), isEmpty);
    expect(probe.asked, isEmpty);
  });

  test('the networks of containers, virtual machines and VPNs are left out', () {
    for (final name in [
      'docker0',
      'br-1a2b3c',
      'veth12ab',
      'virbr0',
      'vmnet8',
      'utun3',
      'tun0',
      'wg0',
      'tailscale0',
      'VirtualBox Host-Only Network',
      'vEthernet (WSL)',
      'VMware Network Adapter VMnet1',
    ]) {
      expect(NetworkWatchFinder.isVirtual(name), isTrue, reason: name);
    }
    for (final name in ['en0', 'en1', 'eth0', 'enp3s0', 'wlp2s0', 'wlan0', 'Wi-Fi', 'Ethernet', 'Ethernet 2']) {
      expect(NetworkWatchFinder.isVirtual(name), isFalse, reason: name);
    }
  });
}
