import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml_events.dart';

import '../api.dart';
import '../util/bytes.dart';
import '../util/mime_base64.dart';
import '../util/zip_reader.dart';
import 'x509.dart';

/// What the watch does with packages signed under a certificate authority.
enum CaPolicy {
  /// The Galaxy Store's: installs.
  store,

  /// A developer certificate's: installs only on the devices listed in it, until it expires.
  deviceBound,

  /// Known, but not tried on a watch.
  unverified,

  /// Not among the roots of Tizen watches.
  untrusted,
}

/// A certificate authority by the common name that issues distributor certificates. With a [fingerprint] (SHA-256 of
/// the authority's own certificate, as hex) a chain naming it must really lead to that certificate.
class KnownCa {
  const KnownCa(this.name, this.policy, [this.fingerprint]);

  final String name;
  final CaPolicy policy;
  final String? fingerprint;
}

/// The authorities that matter on a Galaxy Watch (SM-R800, Tizen 5.5).
const List<KnownCa> knownCas = [
  KnownCa(
    'GEAR2 PROD Public CA Class',
    CaPolicy.store,
    '6F034CB3524D7BFD90AE2AA616067B2228E631ED195E0C332B44BE6C39549634',
  ),
  KnownCa(
    'GEAR2 PROD Platform CA Class',
    CaPolicy.store,
    '0D76E611F6769760E61426F0E7BB3DEBAF1CBA20301F73DD801588844C545468',
  ),
  KnownCa(
    'Samsung Tizen Platform CA Class',
    CaPolicy.unverified,
    '7709F9487171FB834DA175B0D191D8CE980EC4343732DF0AFCE3D1D43AD628C0',
  ),
  KnownCa(
    'Samsung Tizen DEVELOPER Public CA Class',
    CaPolicy.deviceBound,
    '43EFF328726D5C7C58F660A1EBE2987F06932EA04C0EE831EC530710DFDB6CAC',
  ),
  KnownCa(
    'VD DEVELOPER Public CA Class',
    CaPolicy.untrusted,
    'BF18859EB024CC1D63F008DCDDD643077B0DE53E958F35993FF0088D1A1D31AE',
  ),
  KnownCa('Tizen Public Distributor CA', CaPolicy.untrusted),
];

/// Predicts, from the distributor signature alone, whether a Tizen watch accepts a package. It checks the certificate
/// chain in `signature1.xml` against known Samsung authorities and does not verify file digests, so a damaged package
/// can still look fine. The rules come from installs on a Galaxy Watch and are a prediction, not a promise.
///
/// Verdicts: a chain from the store's authority is [SignatureVerdict.storeSigned]; a developer certificate is
/// [SignatureVerdict.deviceBound] or, past its end date, [SignatureVerdict.expired]; an authority watches do not
/// trust, or a chain that only borrows a Samsung authority's name, is [SignatureVerdict.untrusted]; no distributor
/// signature is [SignatureVerdict.unsigned]; an authority not known here, or a signature that cannot be read, is
/// [SignatureVerdict.unknown] (no verdict is better than a wrong one).
class SignatureInspector {
  const SignatureInspector({this.cas = knownCas});

  final List<KnownCa> cas;

  /// A signature lists every file of the package, so real ones reach almost 1 MB.
  static const int _maxSignatureBytes = 8 << 20;
  static const int _dtdScanBytes = 64 * 1024;
  static const int _maxCertificates = 8;
  static final RegExp _distributor = RegExp(r'^signature([1-9][0-9]*)\.xml$');

  /// The verdict for the package at [path] at time [now]; reads synchronously.
  SignatureVerdict inspect(String path, DateTime now) {
    ZipReader? zip;
    try {
      zip = ZipReader.open(path);
      ZipEntry? signature;
      var lowest = 0;
      for (final entry in zip.files) {
        final match = _distributor.firstMatch(entry.name);
        if (match == null) continue;
        // The lowest number is the distributor's own signature; a number too long to read comes last
        final number = int.tryParse(match.group(1)!) ?? (1 << 62);
        if (signature == null || number < lowest) {
          signature = entry;
          lowest = number;
        }
      }
      if (signature == null) return SignatureVerdict.unsigned;
      return assess(_certificates(zip.read(signature, maxBytes: _maxSignatureBytes)), now);
    } catch (_) {
      // Not a zip, a damaged signature, a certificate that cannot be read: no verdict
      return SignatureVerdict.unknown;
    } finally {
      zip?.close();
    }
  }

  /// The verdict for a distributor signature's [certificates], in any order.
  SignatureVerdict assess(List<Certificate> certificates, DateTime now) {
    final chain = _order(certificates);
    if (chain.isEmpty) return SignatureVerdict.unknown;
    final leaf = chain.first;
    final issuer = leaf.issuerCommonName?.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final ca = cas.where((ca) => ca.name.toLowerCase() == issuer).firstOrNull;
    if (ca == null) return SignatureVerdict.unknown;
    final fingerprint = ca.fingerprint;
    if (fingerprint != null) {
      var linked = true;
      for (var i = 0; i + 1 < chain.length; i++) {
        linked = linked && chain[i].isSignedBy(chain[i + 1]);
      }
      final genuine = linked && chain.length > 1 && _fingerprint(chain[1]) == fingerprint.toUpperCase();
      // The issuer's name is a Samsung authority's, but the chain is not that authority's
      if (!genuine) return SignatureVerdict.untrusted;
    }
    return switch (ca.policy) {
      CaPolicy.store => SignatureVerdict.storeSigned,
      CaPolicy.unverified => SignatureVerdict.unknown,
      CaPolicy.untrusted => SignatureVerdict.untrusted,
      CaPolicy.deviceBound => now.isAfter(leaf.notAfter) ? SignatureVerdict.expired : SignatureVerdict.deviceBound,
    };
  }

  /// The certificates of the signature's key information, at most [_maxCertificates].
  static List<Certificate> _certificates(Uint8List bytes) {
    // A DTD can only come before the root element, which is within the first bytes
    final head = latin1.decode(Uint8List.sublistView(bytes, 0, min(bytes.length, _dtdScanBytes))).toLowerCase();
    if (head.contains('<!doctype') || head.contains('<!entity')) throw const FormatException('The signature has a DTD');
    final texts = <String>[];
    StringBuffer? current;
    final events = parseEvents(utf8.decode(bytes, allowMalformed: true), validateNesting: true, validateDocument: true);
    for (final event in events) {
      switch (event) {
        case XmlStartElementEvent(localName: 'X509Certificate', isSelfClosing: true):
          texts.add('');
        case XmlStartElementEvent(localName: 'X509Certificate'):
          current = StringBuffer();
        case XmlTextEvent(:final value) || XmlCDATAEvent(:final value):
          current?.write(value);
        case XmlEndElementEvent(localName: 'X509Certificate'):
          if (current != null) texts.add(current.toString());
          current = null;
        default:
          break;
      }
    }
    return [for (final text in texts.take(_maxCertificates)) Certificate.parse(decodeMimeBase64(text))];
  }

  /// The leaf is the certificate that issued no other one; the rest follow by issuer, and any left over come last.
  static List<Certificate> _order(List<Certificate> certificates) {
    if (certificates.length < 2) return certificates;
    final leaf = certificates
        .where((c) => !certificates.any((other) => !identical(other, c) && sameBytes(other.issuer, c.subject)))
        .firstOrNull;
    if (leaf == null) return certificates;
    final ordered = [leaf];
    final rest = [
      for (final c in certificates)
        if (!identical(c, leaf)) c,
    ];
    while (rest.isNotEmpty) {
      final next = rest.where((c) => sameBytes(c.subject, ordered.last.issuer)).firstOrNull;
      if (next == null) break;
      ordered.add(next);
      rest.remove(next);
    }
    return [...ordered, ...rest];
  }

  static String _fingerprint(Certificate certificate) => sha256.convert(certificate.encoded).toString().toUpperCase();
}
