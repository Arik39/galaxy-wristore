import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/package/zip_package_inspector.dart';

import '../support/zips.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('inspector-test-'));
  tearDown(() => dir.delete(recursive: true));

  final inspector = ZipPackageInspector();
  File zip(Map<String, Object> entries) => writeZip(dir, entries);

  test('a native package is read from tizen-manifest.xml', () async {
    final info = await inspector.read(zip({'tizen-manifest.xml': tpkManifest, 'bin/x': 'elf'}));
    expect(info.type, 'tpk');
    expect(info.packageId, 'com.example.watch');
    expect(info.version, '1.2.3');
    expect(info.displayName, 'Example Face');
    expect(info.iconPath, 'shared/res/face.png');
    expect(info.kind, PackageKind.watchFace);
  });

  test('a web package is read from config.xml', () async {
    final info = await inspector.read(zip({'config.xml': wgtConfig, 'index.html': '<html/>'}));
    expect(info.type, 'wgt');
    expect(info.packageId, 'AbCdEfGhIj');
    expect(info.version, '2.0.1');
    expect(info.displayName, 'Calc');
    expect(info.iconPath, 'img/icon.png');
    expect(info.kind, PackageKind.app);
  });

  test('the kind comes from the manifest: a watch application or the wearable clock category is a face', () async {
    final app = await inspector.read(
      zip({'tizen-manifest.xml': nativeManifestFor('com.example.app', '1.0', face: false)}),
    );
    expect(app.kind, PackageKind.app);
    final webFace = wgtConfig.replaceFirst(
      '<content',
      '<tizen:category name="http://tizen.org/category/wearable_clock"/><content',
    );
    expect((await inspector.read(zip({'config.xml': webFace}))).kind, PackageKind.watchFace);
  });

  test('a wgt that carries a native manifest is treated as native', () async {
    expect((await inspector.read(zip({'config.xml': wgtConfig, 'tizen-manifest.xml': tpkManifest}))).type, 'tpk');
  });

  test('pictures come icon first, then the largest, without sprites or repeats', () async {
    final big = 'B' * 5000;
    final file = zip({
      'tizen-manifest.xml': tpkManifest,
      'res/big.png': big,
      'res/copy-of-big.PNG': big,
      'res/digit.png': 'D' * 300,
      'res/medium.jpg': 'M' * 3000,
      'shared/res/face.png': 'F' * 2000,
      'res/notes.txt': 'T' * 9000,
    });
    List<String> paths(List<PackageImage> images) => [for (final image in images) image.path];
    expect(paths(await inspector.images(file)), ['shared/res/face.png', 'res/big.png', 'res/medium.jpg']);
    expect(paths(await inspector.images(file, maxImages: 1)), ['shared/res/face.png']);
    // A picture over the size limit is skipped, not cut off
    expect(paths(await inspector.images(file, maxBytes: 4000)), ['shared/res/face.png', 'res/medium.jpg']);
    expect(String.fromCharCodes((await inspector.images(file)).first.bytes), 'F' * 2000);
  });

  test('pictures of an archive without a manifest are still pictures', () async {
    final images = await inspector.images(zip({'a.png': 'A' * 2000, 'b.gif': 'B' * 3000}));
    expect(images.map((image) => image.path), ['b.gif', 'a.png']);
  });

  test('archives without a manifest, other files and bad manifests are refused', () async {
    final notZip = File('${dir.path}/junk.wgt')..writeAsBytesSync(List.generate(500, (i) => i));
    final cases = <String, File>{
      'no manifest': zip({'readme.txt': 'hi'}),
      'not a zip': notZip,
      'missing': File('${dir.path}/missing.tpk'),
      'DTD': zip({
        'tizen-manifest.xml':
            '<?xml version="1.0"?><!DOCTYPE manifest [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
            '<manifest package="a.b" version="1"/>',
      }),
      'no package id': zip({'tizen-manifest.xml': '<manifest version="1"/>'}),
      'web without tizen:application': zip({
        'config.xml': '<widget xmlns="http://www.w3.org/ns/widgets" version="1"/>',
      }),
      'too large': zip({'tizen-manifest.xml': '<manifest package="a.b">${' ' * 2000000}</manifest>'}),
      'not UTF-8': zip({
        'tizen-manifest.xml': Uint8List.fromList([0x3c, 0xff, 0xfe, 0x3e]),
      }),
    };
    for (final MapEntry(key: name, value: file) in cases.entries) {
      await expectLater(inspector.read(file), throwsA(isA<InvalidPackageException>()), reason: name);
    }
    await expectLater(inspector.images(notZip), throwsA(isA<InvalidPackageException>()));
  });

  test('random bytes and mangled manifests end in the documented exception and nothing else', () async {
    final random = Random(2);
    for (var i = 0; i < 100; i++) {
      final file = File('${dir.path}/r$i.bin')
        ..writeAsBytesSync(List.generate(random.nextInt(2000), (_) => random.nextInt(256)));
      await expectLater(inspector.read(file), throwsA(isA<InvalidPackageException>()));
    }
    const manifests = [
      '',
      '<manifest',
      '<manifest xmlns="http://tizen.org/ns/packages"/>',
      '<!DOCTYPE x [<!ENTITY a "b">]><manifest xmlns="http://tizen.org/ns/packages" package="&a;"/>',
      '<?xml version="1.0"?><widget xmlns="http://www.w3.org/ns/widgets"/>',
      '\u0000\u0001\u0002',
      '<manifest package="a\u0001b"/>',
    ];
    for (final xml in manifests) {
      for (final entry in ['tizen-manifest.xml', 'config.xml']) {
        await expectLater(
          inspector.read(zip({entry: xml})),
          throwsA(isA<InvalidPackageException>()),
          reason: '$entry: $xml',
        );
      }
    }
  });
}
