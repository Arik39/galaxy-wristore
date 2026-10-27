import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/sdb/key_store.dart';
import 'package:galaxy_wristore/core/sdb/sdb_key.dart';
import 'package:galaxy_wristore/core/util/der.dart';

BigInt _littleEndian(Uint8List bytes) {
  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i]);
  }
  return value;
}

BigInt _bigEndian(List<int> bytes) => bytes.fold(BigInt.zero, (value, byte) => (value << 8) | BigInt.from(byte));

class _FailingStore implements KeyStore {
  @override
  Future<String?> read() async => throw StateError('keychain locked');

  @override
  Future<void> write(String pem) async => throw StateError('keychain locked');
}

void main() {
  late SdbKey key;

  setUpAll(() => key = SdbKey.generate());

  test('the public key struct holds the modulus, its Montgomery constants and the exponent', () {
    final text = ascii.decode(key.adbPublicKey('phone@test'));
    expect(text, endsWith(' phone@test\u0000'));
    final struct = base64.decode(text.substring(0, text.indexOf(' ')));
    expect(struct.length, 4 + 4 + 256 + 256 + 4);
    final view = ByteData.sublistView(struct);
    expect(view.getUint32(0, Endian.little), 64);
    final n0inv = BigInt.from(view.getUint32(4, Endian.little));
    final modulus = _littleEndian(struct.sublist(8, 264));
    final rr = _littleEndian(struct.sublist(264, 520));
    expect(view.getUint32(520, Endian.little), 65537);
    expect(modulus, key.modulus);
    // n0inv * n[0] == -1 (mod 2^32)
    final twoPow32 = BigInt.one << 32;
    expect((n0inv * (modulus % twoPow32)) % twoPow32, twoPow32 - BigInt.one);
    // rr == (2^2048)^2 mod n
    expect(rr, (BigInt.one << 4096) % modulus);
  });

  test('the key name cannot smuggle control characters', () {
    expect(() => key.adbPublicKey('a\nb'), throwsArgumentError);
    expect(() => key.adbPublicKey('Мой телефон'), throwsArgumentError);
  });

  test('a signature is the token under a SHA-1 DigestInfo, verifiable with the public key', () {
    final token = Uint8List.fromList(List.generate(20, (i) => i));
    final signature = key.sign(token);
    expect(signature.length, 256);
    final block = _bigEndian(signature).modPow(key.publicExponent, key.modulus);
    const prefix = [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14];
    final digestInfo = [...prefix, ...token];
    final expected = _bigEndian([0, 1, ...List.filled(256 - 3 - digestInfo.length, 0xff), 0, ...digestInfo]);
    expect(block, expected);
  });

  test('the key survives PEM and signs the same afterwards', () {
    final pem = key.toPem();
    expect(pem, startsWith('-----BEGIN PRIVATE KEY-----\n'));
    final again = SdbKey.fromPem(pem);
    expect(again.modulus, key.modulus);
    final token = Uint8List.fromList(List.filled(20, 9));
    expect(again.sign(token), key.sign(token));
  });

  test('anything but a 2048-bit RSA key in PKCS#8 is refused', () {
    final small = derSequence([
      derInteger(BigInt.zero),
      derSequence([derObjectIdentifier('1.2.840.113549.1.1.1'), derNull()]),
      derOctetString(
        derSequence([
          for (final value in [0, 3233, 17, 413, 61, 53, 53, 49, 38]) derInteger(BigInt.from(value)),
        ]),
      ),
    ]);
    for (final pem in [
      '',
      'hello',
      '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----',
      '-----BEGIN PRIVATE KEY-----\n${base64.encode(small)}\n-----END PRIVATE KEY-----',
      key.toPem().replaceAll('M', 'N'),
    ]) {
      expect(() => SdbKey.fromPem(pem), throwsFormatException, reason: pem);
    }
  });

  test('a key is made once, saved, and the same key read again', () async {
    final store = MemoryKeyStore();
    final first = await loadOrCreateKey(store);
    final pem = await store.read();
    expect(pem, isNotNull);
    final second = await loadOrCreateKey(store);
    expect(second.modulus, first.modulus);
    expect(await store.read(), pem);
  });

  test('a damaged saved key is replaced; a store that cannot be read is an error', () async {
    final store = MemoryKeyStore('-----BEGIN PRIVATE KEY-----\ngarbage\n-----END PRIVATE KEY-----');
    final created = await loadOrCreateKey(store);
    expect(SdbKey.fromPem((await store.read())!).modulus, created.modulus);
    await expectLater(loadOrCreateKey(_FailingStore()), throwsStateError);
  });
}
