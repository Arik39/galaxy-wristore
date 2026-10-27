import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import '../api.dart';
import 'watch_scanner.dart';

/// Finds watches in the network this device is on: its own address and subnet mask give the addresses to probe. The
/// Wi-Fi address comes first. A computer on a cable, or one that cannot tell its Wi-Fi details, uses the private IPv4
/// addresses of its network connections instead; a phone without Wi-Fi does not, as its other address is the mobile
/// network's. In a network that is not private IPv4, it finds nothing.
class NetworkWatchFinder implements WatchFinder {
  /// [localAddresses] replaces the device's own private IPv4 addresses, for tests.
  NetworkWatchFinder({NetworkInfo? info, WatchScanner? scanner, Future<List<String>> Function()? localAddresses})
    : _info = info ?? NetworkInfo(),
      _scanner = scanner ?? WatchScanner(),
      _localAddresses = localAddresses ?? (Platform.isAndroid || Platform.isIOS ? _none : privateAddresses);

  static Future<List<String>> _none() async => const [];

  final NetworkInfo _info;
  final WatchScanner _scanner;
  final Future<List<String>> Function() _localAddresses;

  /// How many of the device's own networks are searched when it has no Wi-Fi address; each adds a few seconds.
  static const int maxNetworks = 2;

  @override
  Future<List<FoundWatch>> find({void Function(double fraction)? onProgress}) async {
    String? own;
    String? mask;
    try {
      own = await _info.getWifiIP();
      if (own != null) mask = await _info.getWifiSubmask();
    } on Exception {
      // Some computers cannot tell their Wi-Fi details; the addresses of their connections serve as well
    }
    if (own != null && WatchAddress.parse(own) != null) {
      // Some phones do not tell the mask; home networks are almost always a /24
      final prefixLength = (mask == null ? null : WatchScanner.prefixLengthOf(mask)) ?? 24;
      return _scanner.scan(WatchScanner.candidates(own, prefixLength), onProgress: onProgress);
    }
    final candidates = <String, WatchAddress>{};
    for (final address in (await _localAddresses()).take(maxNetworks)) {
      for (final candidate in WatchScanner.candidates(address, 24)) {
        candidates[candidate.host] = candidate;
      }
    }
    if (candidates.isEmpty) return const [];
    return _scanner.scan(candidates.values.toList(), onProgress: onProgress);
  }

  /// The device's private IPv4 addresses, those of a home or office network, leaving out the virtual networks of
  /// containers, virtual machines and VPNs, where no watch can be.
  static Future<List<String>> privateAddresses() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final interface in interfaces)
        if (!isVirtual(interface.name))
          for (final address in interface.addresses)
            if (WatchAddress.parse(address.address) != null) address.address,
    ];
  }

  static final _virtual = RegExp(
    r'docker|veth|virbr|^br-|vbox|virtualbox|vmnet|vmware|hyper-v|vethernet|wsl|utun|^tun|^tap|^wg|tailscale|zerotier',
    caseSensitive: false,
  );

  /// Whether a network interface named [name] belongs to a container, a virtual machine or a VPN.
  static bool isVirtual(String name) => _virtual.hasMatch(name);
}
