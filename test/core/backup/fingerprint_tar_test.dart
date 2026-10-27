import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/backup/fingerprint_tar.dart';

void main() {
  late Directory dir;
  late Directory target;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tar-test-');
    target = await Directory('${dir.path}/fingerprints/com.example').create(recursive: true);
  });
  tearDown(() => dir.delete(recursive: true));

  Uint8List tar(List<ArchiveFile> files) {
    final archive = Archive();
    files.forEach(archive.add);
    return TarEncoder().encodeBytes(archive);
  }

  List<String> written() => [
    for (final entity in target.listSync(recursive: true))
      if (entity is File) entity.path.substring(target.path.length + 1),
  ]..sort();

  test('the readable files of an app are unpacked below its folder', () {
    final count = unpackFingerprint(
      tar([
        ArchiveFile.string('tizen-manifest.xml', '<manifest/>'),
        ArchiveFile.directory('shared/res/'),
        ArchiveFile.bytes('shared/res/preview.png', List.filled(2000, 7)),
        ArchiveFile.string('./author-signature.xml', '<Signature/>'),
      ]),
      target.path,
    );
    expect(count, 3);
    expect(written(), ['author-signature.xml', 'shared/res/preview.png', 'tizen-manifest.xml']);
    expect(File('${target.path}/shared/res/preview.png').readAsBytesSync(), List.filled(2000, 7));
  });

  test('links, absolute names and .. parts never reach outside', () {
    unpackFingerprint(
      tar([
        ArchiveFile.symlink('shared', '/etc'),
        ArchiveFile.string('/tmp/evil-absolute', 'x'),
        ArchiveFile.string('../../evil-up', 'x'),
        ArchiveFile.string('shared/../../../evil-middle', 'x'),
        ArchiveFile.string('fine.txt', 'ok'),
      ]),
      target.path,
    );
    expect(written(), ['fine.txt']);
    expect(dir.listSync().map((entity) => entity.path.split('/').last), ['fingerprints']);
    expect(Link('${target.path}/shared').existsSync(), isFalse);
  });

  test('nothing, or too little to be a tar, unpacks nothing', () {
    expect(unpackFingerprint(Uint8List(0), target.path), 0);
    expect(unpackFingerprint(Uint8List.fromList(List.filled(100, 65)), target.path), 0);
    expect(written(), isEmpty);
  });
}
