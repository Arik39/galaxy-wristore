import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_store.dart';

/// Keeps the sdb key in the platform's secure storage (the iOS Keychain, Android's encrypted storage), on this device
/// only: a new phone gets a key of its own, which the watch asks its user to allow once.
class SecureKeyStore implements KeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  final FlutterSecureStorage _storage;

  static const String _name = 'sdb_host_key';

  @override
  Future<String?> read() => _storage.read(key: _name);

  @override
  Future<void> write(String pem) => _storage.write(key: _name, value: pem);
}
