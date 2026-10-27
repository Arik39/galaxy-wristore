import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:galaxy_wristore/core/package/x509.dart';
import 'package:galaxy_wristore/core/util/der.dart';
import 'package:pointycastle/export.dart';

/// A certificate made for a test, with the key that signs the certificates it issues.
class TestPki {
  TestPki._(this.der, this.key);

  final Uint8List der;
  final RSAPrivateKey key;

  Certificate get certificate => Certificate.parse(der);

  /// The certificate in Base64 with line breaks, as `signature1.xml` holds it.
  String get base64Lines {
    final text = base64.encode(der);
    return [for (var i = 0; i < text.length; i += 76) text.substring(i, min(i + 76, text.length))].join('\n');
  }
}

final _random = FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i * 7 + 1))));
var _serial = 1;

/// A certificate for [subject] signed by [issuer] (itself when null). Keys are small, as nothing here needs strength.
TestPki issue(String subject, TestPki? issuer, {required DateTime notAfter, required DateTime notBefore}) {
  final generator = RSAKeyGenerator()
    ..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 12), _random));
  final pair = generator.generateKeyPair();
  // The issuer's own subject name, byte for byte
  final issuerName = issuer == null ? _name(subject) : DerElement.parse(issuer.der).children[0].children[5].encoded;
  final algorithm = derSequence([derObjectIdentifier('1.2.840.113549.1.1.11'), derNull()]);
  final tbs = derSequence([
    derElement(0xa0, derInteger(BigInt.two)),
    derInteger(BigInt.from(_serial++)),
    algorithm,
    issuerName,
    derSequence([_time(notBefore), _time(notAfter)]),
    _name(subject),
    derSequence([
      derSequence([derObjectIdentifier('1.2.840.113549.1.1.1'), derNull()]),
      derElement(0x03, [
        0,
        ...derSequence([derInteger(pair.publicKey.modulus!), derInteger(pair.publicKey.publicExponent!)]),
      ]),
    ]),
  ]);
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(issuer?.key ?? pair.privateKey));
  final signature = signer.generateSignature(tbs).bytes;
  return TestPki._(
    derSequence([
      tbs,
      algorithm,
      derElement(0x03, [0, ...signature]),
    ]),
    pair.privateKey,
  );
}

Uint8List _name(String commonName) => derSequence([
  derElement(0x31, derSequence([derObjectIdentifier('2.5.4.3'), derElement(0x0c, utf8.encode(commonName))])),
]);

Uint8List _time(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final rest = '${two(time.month)}${two(time.day)}${two(time.hour)}${two(time.minute)}${two(time.second)}Z';
  return time.year < 2050
      ? derElement(0x17, ascii.encode('${two(time.year % 100)}$rest'))
      : derElement(0x18, ascii.encode('${time.year}$rest'));
}

/// A `signature1.xml` whose key information holds [certificates].
String signatureXml(List<TestPki> certificates) =>
    '<Signature xmlns="http://www.w3.org/2000/09/xmldsig#"><KeyInfo><X509Data>'
    '${certificates.map((pki) => '<X509Certificate>${pki.base64Lines}</X509Certificate>').join()}'
    '</X509Data></KeyInfo></Signature>';
