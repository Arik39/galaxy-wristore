import 'dart:isolate';

import 'sdb_key.dart';

/// Where the app keeps its sdb key between runs. The watch remembers the key once its user allows this phone, so it
/// must outlive the app's sessions; losing it only means being asked to allow the phone again.
abstract interface class KeyStore {
  /// The key saved last (PKCS#8 PEM), or null before the first one.
  Future<String?> read();

  Future<void> write(String pem);
}

/// A [KeyStore] that forgets everything when the app ends; for tests.
class MemoryKeyStore implements KeyStore {
  MemoryKeyStore([this._pem]);

  String? _pem;

  @override
  Future<String?> read() async => _pem;

  @override
  Future<void> write(String pem) async => _pem = pem;
}

/// The key in [store], made and saved there the first time (in a background isolate, as making one takes a moment).
/// A saved key that cannot be read is replaced; a store that cannot be read is an error, so a passing problem with
/// the platform's secure storage never throws away a key the watch already trusts.
Future<SdbKey> loadOrCreateKey(KeyStore store) async {
  final pem = await store.read();
  if (pem != null) {
    try {
      return SdbKey.fromPem(pem);
    } on FormatException {
      // Damaged: a new key, which the watch asks its user to allow
    }
  }
  final created = await Isolate.run(() => SdbKey.generate().toPem());
  await store.write(created);
  return SdbKey.fromPem(created);
}
