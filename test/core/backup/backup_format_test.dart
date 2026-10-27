import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/backup/backup_format.dart';
import 'package:galaxy_wristore/core/util/zip_reader.dart';

import '../support/zips.dart';

/// A manifest as the Mac app writes it (kotlinx.serialization, pretty, defaults included), with a field from a later
/// version.
const String _macManifest = '''{
    "format": 1,
    "createdAt": "2026-10-26T11:47:51",
    "watch": "device::SM-R800::0",
    "packages": [
        {
            "id": "com.watchface.GSHybrid7",
            "name": "GS Hybrid 7",
            "version": "1.0.1",
            "type": "tpk",
            "origin": "downloaded",
            "entry": "packages/GS Hybrid 7 (com.watchface.GSHybrid7) v1.0.1.tpk",
            "entryVersion": "1.0.1",
            "source": "Tizen Archive",
            "note": null
        },
        {
            "id": "com.samsung.weather",
            "name": "Погода",
            "version": "1.5",
            "type": "tpk",
            "origin": "built_in_updated",
            "entry": null,
            "entryVersion": null,
            "source": null,
            "note": "Not in Tizen Archive: a reset removes it for good."
        }
    ],
    "media": [
        {
            "path": "/opt/usr/home/owner/media/Music/Over the Horizon.mp3",
            "size": 20,
            "entry": "media/Music/Over the Horizon.mp3"
        }
    ],
    "addedLater": {"x": 1}
}''';

BackupPackage _package(String id, String version, {bool copy = true, String name = ''}) => BackupPackage(
  id: id,
  name: name.isEmpty ? id : name,
  version: version,
  type: 'tpk',
  origin: 'downloaded',
  entry: copy ? 'packages/$id.tpk' : null,
  entryVersion: copy ? version : null,
);

void main() {
  test('only the user\'s own files below the media folder count', () {
    expect(mediaRelative('$mediaRoot/Music/Over the Horizon.mp3'), 'Music/Over the Horizon.mp3');
    expect(mediaRelative('$mediaRoot/Images/Screenshot_20260417.jpg'), 'Images/Screenshot_20260417.jpg');
    for (final path in [
      '$mediaRoot/Downloads/.bt_dump/btmon.log',
      '$mediaRoot/.extra/x',
      '$mediaRoot/../etc/passwd',
      '$mediaRoot//double',
      '$mediaRoot/a\nb',
      '$mediaRoot/a,b.mp3',
      '$mediaRoot/',
      '/etc/passwd',
      '${mediaRoot}x/Music/a.mp3',
    ]) {
      expect(mediaRelative(path), isNull, reason: path);
    }
  });

  test('file names keep their extension and fit any file system', () {
    expect(safeFileName('GS Hybrid 7 (com.x) v1.0/2: beta\u0007', 'tpk'), 'GS Hybrid 7 (com.x) v1.0_2_ beta_.tpk');
    final long = safeFileName('a' * 500, 'wgt');
    expect(long, endsWith('.wgt'));
    expect(long.length, 180);
    final wide = safeFileName('時計' * 200, 'tpk');
    expect(wide, endsWith('.tpk'));
    expect(utf8.encode(wide).length, lessThanOrEqualTo(200));
    expect(
      safeFileName('😀' * 200, 'tpk').runes.every((rune) => rune == 0x1f600 || '.tpk'.runes.contains(rune)),
      isTrue,
    );
  });

  test('times are written as the Mac app writes them', () {
    expect(isoLocalDateTime(DateTime(2026, 10, 26, 11, 47, 51, 999)), '2026-10-26T11:47:51');
    expect(isoLocalDateTime(DateTime(2026, 10, 26, 11, 30)), '2026-10-26T11:30');
    expect(backupFileName(DateTime(2026, 1, 2, 3, 4, 5)), 'Watch backup 2026-01-02 0304.twbackup');
    expect(originName(PackageOrigin.builtInUpdated), 'built_in_updated');
  });

  test('a manifest written by the Mac app reads, and one written here reads back the same', () {
    final manifest = decodeManifest(_macManifest);
    expect(manifest.format, 1);
    expect(manifest.createdAt, '2026-10-26T11:47:51');
    expect(manifest.watch, 'device::SM-R800::0');
    expect(manifest.packages.map((package) => package.id), ['com.watchface.GSHybrid7', 'com.samsung.weather']);
    expect(manifest.packages[0].entry, 'packages/GS Hybrid 7 (com.watchface.GSHybrid7) v1.0.1.tpk');
    expect(manifest.packages[1].name, 'Погода');
    expect(manifest.packages[1].origin, 'built_in_updated');
    expect(manifest.packages[1].note, 'Not in Tizen Archive: a reset removes it for good.');
    expect(manifest.media.single.size, 20);

    final written = encodeManifest(manifest);
    expect(written, startsWith('{\n    "format": 1,\n    "createdAt": "2026-10-26T11:47:51",\n'));
    expect(written, contains('"note": null'));
    expect(jsonDecode(written), {...(jsonDecode(_macManifest) as Map<String, Object?>)}..remove('addedLater'));
  });

  test('anything else is not a backup list', () {
    for (final text in [
      '',
      '[]',
      '{"createdAt":"x","watch":"y","packages":[]}',
      '{"createdAt":"x","watch":"y","packages":[{"id":"a"}],"media":[]}',
      '{"createdAt":"x","watch":"y","packages":[],"media":[{"path":"/a","size":-1,"entry":"e"}]}',
      '{"createdAt":"x","watch":"y","packages":[],"media":[{"path":"/a","size":"1","entry":"e"}]}',
      '{"format":"one","createdAt":"x","watch":"y","packages":[],"media":[]}',
    ]) {
      expect(() => decodeManifest(text), throwsFormatException, reason: text);
    }
  });

  test('the report tells what has a copy, what a reset takes for good, and the files', () {
    final text = report(
      BackupManifest(
        createdAt: '2026-10-26T11:30',
        watch: 'device::SM-R800::0',
        packages: [
          _package('com.watchface.GSHybrid7', '1.0.1', name: 'GS Hybrid 7'),
          BackupPackage(
            id: 'com.watchface.GSHybrid6',
            name: 'GS Hybrid 6',
            version: '1.0.1',
            type: 'tpk',
            origin: 'downloaded',
            note: 'Not in Tizen Archive',
          ),
        ],
        media: const [BackupMedia(path: '$mediaRoot/Music/Over the Horizon.mp3', size: 4096, entry: 'media/Music/x')],
      ),
    );
    expect(text, startsWith('Galaxy Watch backup, 2026-10-26 11:30\nWatch: device::SM-R800::0\n'));
    expect(text, contains('  With a copy in this backup (1):\n    GS Hybrid 7 v1.0.1, from null\n'));
    expect(text, contains('Without a copy (1)'));
    expect(text, contains('    GS Hybrid 6 (com.watchface.GSHybrid6) v1.0.1. Not in Tizen Archive\n'));
    expect(text, contains('Your files from the watch: 1 (4 KB)\n    Music/Over the Horizon.mp3\n'));
  });

  test('a restore installs only what the watch lacks or has older', () {
    final plan = planInstalls(
      [
        _package('same', '1.0.1'),
        _package('older', '2.0.0'),
        _package('absent', '1.0.0'),
        _package('lost', '1.0.0', copy: false),
        _package('newer', '1.0.0'),
      ],
      {'same': '1.0.1', 'older': '1.9.9', 'newer': '1.2.0'},
    );
    expect(plan.install.map((package) => package.id), ['older', 'absent']);
    expect(plan.alreadyThere.map((package) => package.id), ['same', 'newer']);
    expect(plan.noCopy.map((package) => package.id), ['lost']);
  });

  test('faces are told from apps by the manifest, the id, or the hands their signature lists', () {
    const face =
        '<manifest package="com.watchface.GSHybrid6"><watch-application appid="x"><icon>GS Hybrid 6.png</icon>'
        '</watch-application></manifest>';
    const app =
        '<manifest package="org.pekdemir.TetriS2"><ui-application appid="y"><icon>TetriS2_icon.png</icon>'
        '</ui-application></manifest>';
    expect(packageKind('com.watchface.GSHybrid6', face), PackageKind.watchFace);
    expect(packageKind('org.pekdemir.TetriS2', app), PackageKind.app);
    expect(packageKind('com.watchface.OV2', null), PackageKind.watchFace);
    expect(packageKind('2048abcdeg', null), PackageKind.app);
    expect(
      packageKind('ru.zakharova.OceanWatchII', null, '<Reference URI="res%2Fhour-hand.png"/>'),
      PackageKind.watchFace,
    );
    expect(packageKind('org.example.app', null, '<Reference URI="res%2Ficon.png"/>'), PackageKind.app);
  });

  test('the picture that shows a package is the icon its manifest names, else the first one there', () async {
    final dir = await Directory.systemTemp.createTemp('format-test-');
    addTearDown(() => dir.delete(recursive: true));
    const face = '<manifest><watch-application><icon> GS Hybrid 6.png </icon></watch-application></manifest>';
    const app = '<manifest><ui-application><icon>TetriS2_icon.png</icon></ui-application></manifest>';
    final zip = ZipReader.open(
      writeZip(dir, {
        'fingerprints/com.watchface.GSHybrid6/shared/res/GS Hybrid 6.png': 'x',
        'fingerprints/com.watchface.GSHybrid6/shared/res/aaa.png': 'x',
        'fingerprints/org.pekdemir.TetriS2/shared/res/b.png': 'x',
        'fingerprints/org.pekdemir.TetriS2/shared/res/a.jpg': 'x',
        'fingerprints/org.pekdemir.TetriS2/shared/res/0.txt': 'x',
      }).path,
    );
    addTearDown(zip.close);
    expect(
      pictureEntry(zip, 'com.watchface.GSHybrid6', face),
      'fingerprints/com.watchface.GSHybrid6/shared/res/GS Hybrid 6.png',
    );
    // The icon the manifest names is missing: the first picture there is
    expect(pictureEntry(zip, 'org.pekdemir.TetriS2', app), 'fingerprints/org.pekdemir.TetriS2/shared/res/a.jpg');
    expect(pictureEntry(zip, 'nothing.here', null), isNull);
  });
}
