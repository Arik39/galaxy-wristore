import 'dart:io';

import 'package:flutter/services.dart';

/// Asks for permission to use the local network, which reaching the watch needs. Android 17 asks the user through
/// this call; iOS asks by itself the first time the app reaches into the network. True when the app may go ahead.
Future<bool> ensureLocalNetwork() async {
  if (!Platform.isAndroid) return true;
  try {
    return await const MethodChannel('app.wristore/local_network').invokeMethod<bool>('request') ?? false;
  } on PlatformException {
    return true;
  } on MissingPluginException {
    return true;
  }
}

/// The user did not allow the local network, so the watch cannot be reached.
class LocalNetworkDenied implements Exception {
  const LocalNetworkDenied();

  String get message =>
      'Galaxy Wristore needs permission to use your local network to reach your watch. Allow it in Settings, Apps, '
      'Galaxy Wristore, Permissions.';

  @override
  String toString() => message;
}
