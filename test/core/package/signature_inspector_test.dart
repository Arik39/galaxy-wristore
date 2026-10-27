import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/package/signature_inspector.dart';
import 'package:galaxy_wristore/core/package/x509.dart';
import 'package:galaxy_wristore/core/package/zip_package_inspector.dart';

import '../support/certificates.dart';
import '../support/zips.dart';
import 'store_chain.dart';

String _fingerprint(TestPki pki) => sha256.convert(pki.der).toString().toUpperCase();

void main() {
  final now = DateTime.utc(2026, 10, 21);
  final notBefore = now.subtract(const Duration(days: 60));
  final notAfter = now.add(const Duration(days: 300));
  TestPki certificate(String subject, TestPki? issuer, {DateTime? until}) =>
      issue(subject, issuer, notBefore: notBefore, notAfter: until ?? notAfter);

  late TestPki root;
  late TestPki goodCa;
  late TestPki devCa;
  late TestPki vdCa;
  late SignatureInspector inspector;

  setUpAll(() {
    root = certificate('Root', null);
    goodCa = certificate('GEAR2 PROD Public CA Class', root);
    devCa = certificate('Samsung Tizen DEVELOPER Public CA Class', root);
    vdCa = certificate('VD DEVELOPER Public CA Class', root);
    inspector = SignatureInspector(
      cas: [
        KnownCa('GEAR2 PROD Public CA Class', CaPolicy.store, _fingerprint(goodCa)),
        KnownCa('Samsung Tizen DEVELOPER Public CA Class', CaPolicy.deviceBound, _fingerprint(devCa)),
        KnownCa('VD DEVELOPER Public CA Class', CaPolicy.untrusted, _fingerprint(vdCa)),
        const KnownCa('Tizen Public Distributor CA', CaPolicy.untrusted),
      ],
    );
  });

  SignatureVerdict assess(List<TestPki> chain) => inspector.assess([for (final pki in chain) pki.certificate], now);

  test('a store signature from the genuine authority is store-signed, in any order', () {
    final leaf = certificate('GEAR2 PROD Public Signer Class', goodCa);
    expect(assess([leaf, goodCa]), SignatureVerdict.storeSigned);
    expect(assess([goodCa, leaf]), SignatureVerdict.storeSigned);
    expect(assess([leaf, goodCa, root]), SignatureVerdict.storeSigned);
  });

  test('a chain that only borrows a Samsung authority\'s name is untrusted', () {
    final leaf = certificate('Signer', goodCa);
    // A lone leaf
    expect(assess([leaf]), SignatureVerdict.untrusted);
    // An imitation of the authority
    final fakeCa = certificate('GEAR2 PROD Public CA Class', root);
    expect(assess([certificate('Signer', fakeCa), fakeCa]), SignatureVerdict.untrusted);
    // The genuine authority, but another key signed the leaf
    expect(assess([certificate('Signer', fakeCa), goodCa]), SignatureVerdict.untrusted);
  });

  test('a developer certificate is device-bound until its end date, then expired', () {
    expect(assess([certificate('TizenSDK', devCa), devCa]), SignatureVerdict.deviceBound);
    final old = certificate('TizenSDK', devCa, until: now.subtract(const Duration(days: 10)));
    expect(assess([old, devCa]), SignatureVerdict.expired);
  });

  test('VD developer and Tizen SDK certificates are untrusted by the watch', () {
    expect(assess([certificate('Dev', vdCa), vdCa]), SignatureVerdict.untrusted);
    final sdk = certificate('Tizen Public Distributor CA', root);
    expect(assess([certificate('Developer', sdk), sdk]), SignatureVerdict.untrusted);
  });

  test('an unknown authority gives no verdict', () {
    final ca = certificate('Some Other CA', root);
    expect(assess([certificate('Signer', ca), ca]), SignatureVerdict.unknown);
    expect(inspector.assess(const [], now), SignatureVerdict.unknown);
  });

  test('the real store chain is recognised by the authority\'s known fingerprint', () {
    final chain = [
      for (final text in [storeAuthority, storeSigner]) Certificate.parse(base64.decode(text)),
    ];
    expect(chain[1].issuerCommonName, 'GEAR2 PROD Public CA Class');
    expect(chain[1].isSignedBy(chain[0]), isTrue);
    expect(chain[0].isSignedBy(chain[1]), isFalse);
    expect(const SignatureInspector().assess(chain, now), SignatureVerdict.storeSigned);
  });

  group('in a package', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('signature-test-'));
    tearDown(() => dir.delete(recursive: true));

    final packages = ZipPackageInspector(clock: () => now);

    test('a store package\'s signature1.xml is read', () async {
      final signature =
          '<Signature xmlns="http://www.w3.org/2000/09/xmldsig#"><KeyInfo><X509Data>'
          '<X509Certificate>$storeSigner</X509Certificate><X509Certificate>\n$storeAuthority\n</X509Certificate>'
          '</X509Data></KeyInfo></Signature>';
      final file = writeZip(dir, {'tizen-manifest.xml': tpkManifest, 'signature1.xml': signature});
      expect(await packages.signature(file), SignatureVerdict.storeSigned);
    });

    test('a package without a distributor signature is unsigned', () async {
      final file = writeZip(dir, {'config.xml': '<widget/>', 'author-signature.xml': '<Signature/>'});
      expect(await packages.signature(file), SignatureVerdict.unsigned);
    });

    test('an unreadable signature gives no verdict', () async {
      for (final xml in [
        '<not xml',
        '<!DOCTYPE x [<!ENTITY a "b">]><x/>',
        '<Signature><X509Certificate>AAAA</X509Certificate></Signature>',
        '<Signature><X509Certificate>not base64!</X509Certificate></Signature>',
        '<Signature><X509Certificate>',
      ]) {
        expect(await packages.signature(writeZip(dir, {'signature1.xml': xml})), SignatureVerdict.unknown, reason: xml);
      }
      final notZip = File('${dir.path}/x.bin')..writeAsBytesSync([1, 2, 3]);
      expect(await packages.signature(notZip), SignatureVerdict.unknown);
    });

    test('the lowest numbered signature is the distributor\'s', () async {
      final leaf = certificate('Signer', certificate('Whatever CA', root));
      final file = writeZip(dir, {
        'signature2.xml': '<broken',
        'signature1.xml': signatureXml([leaf]),
        'signature0.xml': '<x',
      });
      // Synthetic authorities are not known to the real table, so the issuer is simply not recognised
      expect(await packages.signature(file), SignatureVerdict.unknown);
      final broken = writeZip(dir, {
        'signature1.xml': '<broken',
        'signature2.xml': signatureXml([leaf]),
      });
      expect(await packages.signature(broken), SignatureVerdict.unknown);
    });
  });
}
