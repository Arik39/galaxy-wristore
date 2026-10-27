import 'package:network_info_plus/network_info_plus.dart';

import '../api.dart';
import 'watch_scanner.dart';

/// Finds watches in the phone's Wi-Fi network: the phone's own Wi-Fi address and subnet mask give the addresses to
/// probe. Without Wi-Fi, or in a network that is not private IPv4, it finds nothing.
class NetworkWatchFinder implements WatchFinder {
  NetworkWatchFinder({NetworkInfo? info, WatchScanner? scanner})
    : _info = info ?? NetworkInfo(),
      _scanner = scanner ?? WatchScanner();

  final NetworkInfo _info;
  final WatchScanner _scanner;

  @override
  Future<List<FoundWatch>> find({void Function(double fraction)? onProgress}) async {
    final own = await _info.getWifiIP();
    if (own == null) return const [];
    final mask = await _info.getWifiSubmask();
    // Some phones do not tell the mask; home networks are almost always a /24
    final prefixLength = (mask == null ? null : WatchScanner.prefixLengthOf(mask)) ?? 24;
    return _scanner.scan(WatchScanner.candidates(own, prefixLength), onProgress: onProgress);
  }
}
