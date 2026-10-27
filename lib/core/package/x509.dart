import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../util/der.dart';

/// The parts of an X.509 certificate that tell where a package's signature comes from. Only reading: nothing here
/// decides whether a certificate is to be trusted.
class Certificate {
  Certificate._({
    required this.encoded,
    required this.issuer,
    required this.subject,
    required this.issuerCommonName,
    required this.notAfter,
    required this._signedPart,
    required this._signatureAlgorithm,
    required this._signature,
    required this._rsaKey,
  });

  /// The whole certificate, as its fingerprint is taken.
  final Uint8List encoded;

  /// The issuer's and the subject's names as encoded, compared byte for byte to link a chain.
  final Uint8List issuer;
  final Uint8List subject;

  /// The issuer's common name (the most specific one when there are several); null without one.
  final String? issuerCommonName;
  final DateTime notAfter;

  final Uint8List _signedPart;
  final String _signatureAlgorithm;
  final Uint8List _signature;
  final RSAPublicKey? _rsaKey;

  static const String _commonName = '2.5.4.3';
  static const String _rsaEncryption = '1.2.840.113549.1.1.1';

  /// RSA PKCS#1 v1.5 signature algorithms: the digest and its DER-encoded identifier.
  static const Map<String, (String, String)> _rsaSignatures = {
    '1.2.840.113549.1.1.4': ('MD5', '06082a864886f70d0205'),
    '1.2.840.113549.1.1.5': ('SHA-1', '06052b0e03021a'),
    '1.2.840.113549.1.1.14': ('SHA-224', '0609608648016503040204'),
    '1.2.840.113549.1.1.11': ('SHA-256', '0609608648016503040201'),
    '1.2.840.113549.1.1.12': ('SHA-384', '0609608648016503040202'),
    '1.2.840.113549.1.1.13': ('SHA-512', '0609608648016503040203'),
  };

  /// Reads a DER certificate; [FormatException] for anything that is not one.
  static Certificate parse(Uint8List der) {
    try {
      return _parse(der);
    } on FormatException {
      rethrow;
    } catch (_) {
      // A structure of the wrong shape (too few elements, a wrong type)
      throw const FormatException('Not an X.509 certificate');
    }
  }

  static Certificate _parse(Uint8List der) {
    final certificate = DerElement.parse(der);
    final parts = certificate.children;
    if (parts.length != 3) throw const FormatException('Not an X.509 certificate');
    final fields = parts[0].children;
    // An explicit version comes first in a v2 or v3 certificate; the serial number and inner algorithm follow
    var i = fields.first.tag == 0xa0 ? 3 : 2;
    final issuer = fields[i++];
    final validity = fields[i++].children;
    final subject = fields[i++];
    final publicKeyInfo = fields[i].children;
    return Certificate._(
      encoded: certificate.encoded,
      issuer: issuer.encoded,
      subject: subject.encoded,
      issuerCommonName: _lastCommonName(issuer),
      notAfter: validity[1].time,
      signedPart: parts[0].encoded,
      signatureAlgorithm: parts[1].children.first.objectIdentifier,
      signature: parts[2].bitString,
      rsaKey: _readRsaKey(publicKeyInfo),
    );
  }

  /// Whether [parent]'s key made this certificate's signature. Only RSA signatures, the kind Samsung's Tizen
  /// certificate authorities use, are checked; any other is taken as not made by [parent].
  bool isSignedBy(Certificate parent) {
    final key = parent._rsaKey;
    final algorithm = _rsaSignatures[_signatureAlgorithm];
    if (key == null || algorithm == null) return false;
    final (digestName, digestIdentifier) = algorithm;
    final digest = switch (digestName) {
      'MD5' => MD5Digest(),
      'SHA-1' => SHA1Digest(),
      'SHA-224' => SHA224Digest(),
      'SHA-256' => SHA256Digest(),
      'SHA-384' => SHA384Digest(),
      _ => SHA512Digest(),
    } as Digest;
    try {
      final signer = RSASigner(digest, digestIdentifier)..init(false, PublicKeyParameter<RSAPublicKey>(key));
      return signer.verifySignature(_signedPart, RSASignature(_signature));
    } catch (_) {
      // A signature of the wrong size or shape for the key
      return false;
    }
  }

  /// The common names of an RFC 2253 rendering come last-first, and the one shown first is the one a name is known
  /// by: so the last in the encoding.
  static String? _lastCommonName(DerElement name) {
    String? found;
    for (final attribute in name.children.expand((relativeName) => relativeName.children)) {
      final pair = attribute.children;
      if (pair.length == 2 && pair[0].objectIdentifier == _commonName) found = pair[1].text;
    }
    return found;
  }

  static RSAPublicKey? _readRsaKey(List<DerElement> publicKeyInfo) {
    if (publicKeyInfo.length != 2 || publicKeyInfo[0].children.first.objectIdentifier != _rsaEncryption) return null;
    final numbers = DerElement.parse(publicKeyInfo[1].bitString).children;
    if (numbers.length != 2) return null;
    final modulus = numbers[0].integer;
    final exponent = numbers[1].integer;
    return modulus > BigInt.zero && exponent > BigInt.zero ? RSAPublicKey(modulus, exponent) : null;
  }
}
