import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../util/der.dart';

/// The app's sdb host key: a 2048-bit RSA key the watch learns when its user allows this phone.
class SdbKey {
  SdbKey._(this._private, this._publicExponent);

  final RSAPrivateKey _private;
  final BigInt _publicExponent;

  static const int bits = 2048;
  static const String _rsaEncryption = '1.2.840.113549.1.1.1';

  /// The DigestInfo of a SHA-1 hash, without the hash: the watch's token takes the hash's place.
  static const List<int> _sha1DigestInfo = [
    0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14, //
  ];

  BigInt get modulus => _private.modulus!;

  BigInt get publicExponent => _publicExponent;

  /// A new key with public exponent 65537. It takes a moment: run it in a background isolate.
  static SdbKey generate() {
    final random = FortunaRandom()..seed(KeyParameter(_entropy(32)));
    final generator = RSAKeyGenerator()
      ..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64), random));
    final pair = generator.generateKeyPair();
    return SdbKey._(pair.privateKey, pair.publicKey.publicExponent!);
  }

  /// Signs the token of an AUTH request: RSA PKCS#1 v1.5 over a SHA-1 DigestInfo with the token as the hash, which
  /// is what the watch checks (the token is not hashed again).
  Uint8List sign(Uint8List token) {
    final cipher = PKCS1Encoding(RSAEngine())..init(true, PrivateKeyParameter<RSAPrivateKey>(_private));
    return cipher.process(Uint8List.fromList([..._sha1DigestInfo, ...token]));
  }

  /// The public key as the watch's sdbd accepts it in an AUTH public-key packet: Android's `RSAPublicKey` struct
  /// (little-endian, with the Montgomery constants the device uses) in Base64, a space, [name] and a NUL.
  Uint8List adbPublicKey(String name) {
    final n = modulus;
    if (name.codeUnits.any((c) => c < 0x20 || c > 0x7e)) {
      throw ArgumentError.value(name, 'name', 'The key name must be printable ASCII');
    }
    const words = bits ~/ 32;
    final twoPow32 = BigInt.one << 32;
    final r = BigInt.one << bits;
    final rr = (r * r) % n;
    final n0inv = (twoPow32 - (n % twoPow32).modInverse(twoPow32)) % twoPow32;
    final struct = Uint8List(4 + 4 + bits ~/ 8 + bits ~/ 8 + 4);
    ByteData.sublistView(struct)
      ..setUint32(0, words, Endian.little)
      ..setUint32(4, n0inv.toInt(), Endian.little)
      ..setUint32(struct.length - 4, _publicExponent.toInt(), Endian.little);
    struct
      ..setRange(8, 8 + bits ~/ 8, _littleEndian(n, bits ~/ 8))
      ..setRange(8 + bits ~/ 8, 8 + 2 * (bits ~/ 8), _littleEndian(rr, bits ~/ 8));
    return ascii.encode('${base64.encode(struct)} $name\u0000');
  }

  /// The key as PKCS#8 PEM ("PRIVATE KEY"), the form the platform's secure storage keeps.
  String toPem() {
    final p = _private.p!;
    final q = _private.q!;
    final d = _private.privateExponent!;
    final rsaKey = derSequence([
      derInteger(BigInt.zero),
      derInteger(modulus),
      derInteger(_publicExponent),
      derInteger(d),
      derInteger(p),
      derInteger(q),
      derInteger(d % (p - BigInt.one)),
      derInteger(d % (q - BigInt.one)),
      derInteger(q.modInverse(p)),
    ]);
    final info = derSequence([
      derInteger(BigInt.zero),
      derSequence([derObjectIdentifier(_rsaEncryption), derNull()]),
      derOctetString(rsaKey),
    ]);
    final text = base64.encode(info);
    final lines = [for (var i = 0; i < text.length; i += 64) text.substring(i, min(i + 64, text.length))];
    return '-----BEGIN PRIVATE KEY-----\n${lines.join('\n')}\n-----END PRIVATE KEY-----\n';
  }

  /// Reads a key written by [toPem]; [FormatException] for anything else, including keys that are not 2048-bit RSA.
  static SdbKey fromPem(String pem) {
    try {
      return _fromPem(pem);
    } on FormatException {
      rethrow;
    } catch (_) {
      // A structure of the wrong shape, or numbers that are no RSA key
      throw const FormatException('Damaged private key');
    }
  }

  static SdbKey _fromPem(String pem) {
    final match = RegExp(r'-----BEGIN PRIVATE KEY-----([A-Za-z0-9+/=\s]+)-----END PRIVATE KEY-----').firstMatch(pem);
    if (match == null) throw const FormatException('Not a PKCS#8 private key');
    final info = DerElement.parse(base64.decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''))).children;
    if (info.length < 3 || info[1].children.first.objectIdentifier != _rsaEncryption) {
      throw const FormatException('Not an RSA private key');
    }
    final octets = info[2];
    if (octets.tag != DerElement.octetStringTag) throw const FormatException('Not an RSA private key');
    final fields = DerElement.parse(octets.content).children;
    if (fields.length < 9) throw const FormatException('Incomplete RSA private key');
    final n = fields[1].integer;
    final e = fields[2].integer;
    final p = fields[4].integer;
    final q = fields[5].integer;
    if (n.bitLength != bits || p * q != n || e <= BigInt.one) throw const FormatException('Not a 2048-bit RSA key');
    return SdbKey._(RSAPrivateKey(n, fields[3].integer, p, q), e);
  }

  static Uint8List _littleEndian(BigInt value, int length) {
    final out = Uint8List(length);
    final mask = BigInt.from(0xff);
    var rest = value;
    for (var i = 0; i < length; i++) {
      out[i] = (rest & mask).toInt();
      rest >>= 8;
    }
    return out;
  }

  static Uint8List _entropy(int length) {
    final random = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < length; i++) random.nextInt(256)]);
  }
}
