import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_store.dart';

/// Keeps the sdb key in the platform's secure storage (the Keychain on iOS and macOS, Android's encrypted storage, the
/// Windows credential store, the Secret Service on Linux), on this device only: a new phone or computer gets a key of
/// its own, which the watch asks its user to allow once.
class SecureKeyStore implements KeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            // The data protection keychain needs an app signed by a paid developer account; the Mac app is not, so it
            // keeps its key in the login keychain.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  static const String _name = 'sdb_host_key';

  @override
  Future<String?> read() => _storage.read(key: _name);

  @override
  Future<void> write(String pem) => _storage.write(key: _name, value: pem);
}
