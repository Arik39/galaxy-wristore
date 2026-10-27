import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/backup/backup_format.dart';
import 'package:galaxy_wristore/core/backup/tw_backup_service.dart';
import 'package:galaxy_wristore/core/package/zip_package_inspector.dart';
import 'package:galaxy_wristore/core/util/bytes.dart';
import 'package:galaxy_wristore/core/util/zip_reader.dart';

import '../support/fakes.dart';
import '../support/zips.dart';

const _mp3Path = '$mediaRoot/Music/Over the Horizon.mp3';
const _findCommand = "find $mediaRoot -type f -printf '%s\\t%p\\n' 2>/dev/null";

String _tarCommand(String id) =>
    'cd /opt/usr/globalapps/$id && tar -cf - --exclude=locale tizen-manifest.xml '
    'author-signature.xml signature1.xml signature2.xml shared/res 2>/dev/null | base64';

/// Base64 as the watch's `base64` prints it: lines of 76 characters.
String _base64Lines(List<int> bytes) {
  final text = base64.encode(bytes);
  return [for (var i = 0; i < text.length; i += 76) text.substring(i, min(i + 76, text.length))].join('\n');
}

WatchPackage _watchPackage(String id, String name, String version, PackageOrigin origin, {String type = 'tpk'}) =>
    WatchPackage(id: id, name: name, version: version, type: type, origin: origin);

void main() {
  final preview = Uint8List.fromList(List.filled(2000, 1));
  final background = Uint8List.fromList(List.filled(3000, 2));
  final mp3 = Uint8List.fromList(List.generate(20000, (i) => i % 251));
  final hybrid7 = zipBytes({
    'tizen-manifest.xml': nativeManifestFor('com.watchface.GSHybrid7', '1.0.1', icon: 'preview.png'),
    'shared/res/preview.png': preview,
    'res/background.png': background,
    'res/digit.png': Uint8List(100),
  });
  final weather = zipBytes({'tizen-manifest.xml': nativeManifestFor('com.samsung.weather', '1.6', face: false)});
  final mine = zipBytes({'tizen-manifest.xml': nativeManifestFor('org.mine.App', '2.0', face: false)});

  late Directory dir;
  late Directory extras;
  late FakeCatalog catalog;
  late TwBackupService service;

  Artifact artifact(String url, Uint8List bytes, Verdict verdict) =>
      Artifact(downloadUrl: url, sha256: sha256.convert(bytes).toString(), size: bytes.length, verdict: verdict);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup-test-');
    extras = await Directory('${dir.path}/extras').create();
    File('${extras.path}/myapp.tpk').writeAsBytesSync(mine);
    File('${extras.path}/notes.txt').writeAsStringSync('not a package');
    File('${extras.path}/broken.wgt').writeAsStringSync('not a package either');
    catalog = FakeCatalog()
      ..versions['com.watchface.GSHybrid7'] = [
        VersionInfo(
          id: 'com.watchface.GSHybrid7',
          version: '1.0.1',
          name: 'GS Hybrid 7',
          artifacts: [artifact('/api/artifacts/h7/download', hybrid7, Verdict.installable)],
          buildVerdicts: const [Verdict.installable],
        ),
      ]
      ..versions['com.samsung.weather'] = [
        VersionInfo(
          id: 'com.samsung.weather',
          version: '1.6',
          name: 'Weather',
          artifacts: [artifact('/api/artifacts/w/download', weather, Verdict.installable)],
          buildVerdicts: const [Verdict.installable],
        ),
      ]
      ..versions['lost.Face'] = [
        VersionInfo(
          id: 'lost.Face',
          version: '1.0',
          artifacts: [artifact('/api/artifacts/l/download', mine, Verdict.deviceBound)],
          buildVerdicts: const [Verdict.deviceBound],
        ),
      ]
      ..files['/api/artifacts/h7/download'] = hybrid7
      ..files['/api/artifacts/w/download'] = weather;
    service = TwBackupService(
      catalog: catalog,
      inspector: ZipPackageInspector(),
      cache: Directory('${dir.path}/cache'),
      clock: () => DateTime(2026, 10, 26, 11, 30),
    );
  });
  tearDown(() => dir.delete(recursive: true));

  /// The owner's watch: five apps and faces (one built in), a file of music, and a few things a backup leaves out.
  T watchWithApps<T extends FakeWatch>(T watch) {
    watch.packages.addAll([
      _watchPackage('com.watchface.GSHybrid7', 'GS Hybrid 7', '1.0.1', PackageOrigin.downloaded),
      _watchPackage('org.mine.App', 'My App', '2.0', PackageOrigin.downloaded),
      _watchPackage('com.samsung.weather', 'Weather', '1.5', PackageOrigin.builtInUpdated),
      _watchPackage('com.samsung.clock', 'Clock', '1.0', PackageOrigin.builtIn),
      _watchPackage('lost.Face', 'Lost Face', '1.0', PackageOrigin.downloaded, type: 'wgt'),
    ]);
    final ids = ['com.watchface.GSHybrid7', 'org.mine.App', 'com.samsung.weather', 'com.samsung.clock', 'lost.Face'];
    watch.shells['ls -1 /opt/usr/globalapps'] = '${ids.join('\n')}\nbad;id\n';
    for (final id in ids) {
      watch.shells['pkginfo --pkg $id 2>&1'] = 'Preload: 0\r\nupdate: 0\r\n';
    }
    final readable = Archive()
      ..add(
        ArchiveFile.string(
          'tizen-manifest.xml',
          nativeManifestFor('com.watchface.GSHybrid7', '1.0.1', icon: 'preview.png'),
        ),
      )
      ..add(ArchiveFile.bytes('shared/res/preview.png', preview));
    watch
      ..shells[_tarCommand('com.watchface.GSHybrid7')] = _base64Lines(TarEncoder().encodeBytes(readable))
      ..shellFailures[_tarCommand('lost.Face')] = const WatchException(
        WatchError.protocol,
        'The command printed too much',
      )
      ..shells['base64 /opt/dbspace/.pkgmgr_cert.db 2>/dev/null'] = _base64Lines(utf8.encode('SQLite format 3'))
      ..shells[_findCommand] =
          '20000\t$_mp3Path\n'
          '5\t$mediaRoot/.hidden/log\n'
          '7\t$mediaRoot/Images/a,b.jpg\n'
          '3\t$mediaRoot/gone.txt\r\n'
      ..files[_mp3Path] = mp3;
    return watch;
  }

  Future<File> backUp(FakeWatch watch, [RecordedProgress? progress]) => service.create(
    watch,
    Directory('${dir.path}/out'),
    extraPackages: extras,
    progress: progress ?? RecordedProgress(),
  );

  test('a backup is one file with copies, the user\'s files and a fingerprint of every app', () async {
    final watch = watchWithApps(StreamingFakeWatch());
    final progress = RecordedProgress();
    final file = await backUp(watch, progress);

    expect(file.path, '${dir.path}/out/Watch backup 2026-10-26 1130.twbackup');
    expect(Directory('${dir.path}/out').listSync().map((entity) => entity.path.split('/').last), [
      'Watch backup 2026-10-26 1130.twbackup',
    ]);
    final zip = ZipReader.open(file.path);
    addTearDown(zip.close);
    Uint8List entry(String name) => zip.read(zip[name]!, maxBytes: 1 << 20);

    final manifest = readManifest(zip);
    expect(manifest.createdAt, '2026-10-26T11:30');
    expect(manifest.watch, 'device::SM-R800::0');
    expect(manifest.packages.map((package) => (package.id, package.origin)), [
      ('com.watchface.GSHybrid7', 'downloaded'),
      ('org.mine.App', 'downloaded'),
      ('com.samsung.weather', 'built_in_updated'),
      ('lost.Face', 'downloaded'),
    ]);
    final [face, app, updated, lost] = manifest.packages;
    expect(face.entry, 'packages/GS Hybrid 7 (com.watchface.GSHybrid7) v1.0.1.tpk');
    expect([face.entryVersion, face.source, face.note], ['1.0.1', 'Tizen Archive', null]);
    expect(entry(face.entry!), hybrid7);
    expect(app.entry, 'packages/My App (org.mine.App) v2.0.tpk');
    expect(app.source, 'your file myapp.tpk');
    expect(app.note, 'This file is not store-signed: the watch may refuse it.');
    expect(entry(app.entry!), mine);
    expect(updated.entry, 'packages/Weather (com.samsung.weather) v1.6.tpk');
    expect(updated.note, 'The watch has v1.5; Tizen Archive has v1.6.');
    expect(lost.entry, isNull);
    expect(
      lost.note,
      'Tizen Archive has it (v1.0 device bound) but no copy fit for this watch: a reset removes it for good.',
    );

    expect(manifest.media.map((media) => (media.path, media.size, media.entry)), [
      (_mp3Path, 20000, 'media/Music/Over the Horizon.mp3'),
    ]);
    expect(entry('media/Music/Over the Horizon.mp3'), mp3);
    expect(watch.streamedPulls, 1);

    expect(utf8.decode(entry('fingerprints/com.watchface.GSHybrid7/pkginfo.txt')), 'Preload: 0\nupdate: 0\n');
    expect(entry('fingerprints/com.watchface.GSHybrid7/shared/res/preview.png'), preview);
    expect(zip['fingerprints/com.watchface.GSHybrid7/tizen-manifest.xml'], isNotNull);
    expect(zip['fingerprints/com.samsung.clock/pkginfo.txt'], isNotNull);
    expect(utf8.decode(entry('fingerprints/lost.Face/skipped.txt')), contains('too large'));
    expect(utf8.decode(entry('fingerprints/_certificate-database/pkgmgr_cert.db')), 'SQLite format 3');
    expect(zip['fingerprints/_certificate-database/pkgmgr_cert.db-journal'], isNull);
    expect(utf8.decode(entry('report.txt')), contains('Without a copy (1)'));
    expect(zip.files.where((entry) => entry.name.contains('bad;id') || entry.name.contains('download')), isEmpty);
    // Nothing the watch printed went into a command
    expect(watch.commands.where((command) => command.contains('bad;id')), isEmpty);

    expect(
      progress.steps,
      containsAllInOrder([
        'Reading the packages on the watch…',
        'Fingerprint 1 of 5: GS Hybrid 7',
        'File 1 of 2: Music/Over the Horizon.mp3',
        'File 2 of 2: gone.txt',
        'Copy 1 of 4: GS Hybrid 7',
        'Writing the backup file…',
      ]),
    );
    expect(progress.steps, contains(startsWith('gone.txt could not be read')));
  });

  test('a second backup takes Tizen Archive\'s files from the cache and replaces one of the same minute', () async {
    await backUp(watchWithApps(StreamingFakeWatch()));
    expect(catalog.downloads, ['/api/artifacts/h7/download', '/api/artifacts/w/download']);
    final again = await backUp(watchWithApps(StreamingFakeWatch()));
    expect(catalog.downloads, hasLength(2));
    final zip = ZipReader.open(again.path);
    addTearDown(zip.close);
    expect(zip.read(zip['packages/GS Hybrid 7 (com.watchface.GSHybrid7) v1.0.1.tpk']!, maxBytes: 1 << 20), hybrid7);
  });

  test(
    'a connection that cannot stream files still has its files backed up, and an unreachable catalog is noted',
    () async {
      catalog.failure = const CatalogException('Network error: offline');
      final file = await backUp(watchWithApps(FakeWatch()));
      final zip = ZipReader.open(file.path);
      addTearDown(zip.close);
      expect(zip.read(zip['media/Music/Over the Horizon.mp3']!, maxBytes: 1 << 20), mp3);
      final face = readManifest(zip).packages.first;
      expect(face.entry, isNull);
      expect(face.note, 'Tizen Archive could not be asked (Network error: offline): back up again later.');
    },
  );

  test('a lost connection ends the backup and leaves nothing behind', () async {
    final watch = watchWithApps(StreamingFakeWatch())
      ..shellFailures[_findCommand] = const WatchException(WatchError.lost, 'The watch stopped answering');
    await expectLater(backUp(watch), throwsA(isA<WatchException>()));
    expect(Directory('${dir.path}/out').existsSync(), isFalse);
  });

  group('an opened backup', () {
    late BackupContents contents;
    setUp(() async {
      contents = await service.open(await backUp(watchWithApps(StreamingFakeWatch())));
      addTearDown(contents.close);
    });

    test('lists the packages with a copy, faces first, then by name', () {
      expect(contents.manifest.packages, hasLength(4));
      expect(contents.items.map((item) => (item.package.name, item.kind)), [
        ('GS Hybrid 7', PackageKind.watchFace),
        ('My App', PackageKind.app),
        ('Weather', PackageKind.app),
      ]);
      expect(contents.items.first.manifestXml, contains('<watch-application'));
    });

    test('shows each package by the picture its fingerprint has, then those in its file, each once', () async {
      final [face, app, _] = contents.items;
      expect(await contents.thumbnail(face), preview);
      expect(await contents.pictures(face), [preview, background]);
      expect(await contents.thumbnail(app), isNull);
      expect(await contents.pictures(app), isEmpty);
    });

    test('gives the user\'s files back for previews, within a size', () async {
      final media = contents.manifest.media.single;
      expect(await contents.mediaBytes(media), mp3);
      expect(await contents.mediaBytes(media, maxBytes: 100), isNull);
      expect(await contents.mediaBytes(const BackupMedia(path: '$mediaRoot/x', size: 1, entry: 'media/x')), isNull);
    });

    test('cannot be read once closed', () async {
      await contents.close();
      expect(() => contents.thumbnail(contents.items.first), throwsStateError);
    });
  });

  test('a file that is not a backup does not open', () async {
    final noList = writeZip(dir, {'readme.txt': 'hello'});
    final notZip = File('${dir.path}/junk.twbackup')..writeAsStringSync('junk');
    await expectLater(service.open(noList), throwsFormatException);
    await expectLater(service.open(notZip), throwsFormatException);
  });

  group('a restore', () {
    late File backup;
    setUp(() async => backup = await backUp(watchWithApps(StreamingFakeWatch())));

    const everything = {'com.watchface.GSHybrid7', 'org.mine.App', 'com.samsung.weather', 'lost.Face'};

    test('installs only what the watch lacks or has older, and copies back the files chosen', () async {
      final watch = StreamingFakeWatch()
        ..packages.addAll([
          _watchPackage('com.watchface.GSHybrid7', 'GS Hybrid 7', '1.0.1', PackageOrigin.downloaded),
          _watchPackage('com.samsung.weather', 'Weather', '1.5', PackageOrigin.builtIn),
        ]);
      final progress = RecordedProgress();
      final result = await service.restore(
        watch,
        backup,
        packageIds: everything,
        mediaPaths: {_mp3Path},
        progress: progress,
      );
      expect(result.installed, ['My App', 'Weather']);
      expect(result.alreadyThere, ['GS Hybrid 7']);
      expect(result.noCopy, ['Lost Face']);
      expect(result.failed, isEmpty);
      expect(watch.installed, [mine, weather]);
      expect(result.filesCopied, 1);
      expect(watch.uploads[_mp3Path], mp3);
      expect(progress.steps, contains('Installing 1 of 2: My App…'));
      expect(progress.steps, contains('Copying back 1 of 1: Music/Over the Horizon.mp3'));
    });

    test('puts back nothing that was not chosen, and skips files the watch already has', () async {
      final watch = StreamingFakeWatch()..shells[_findCommand] = '20000\t$_mp3Path\n';
      final result = await service.restore(watch, backup, mediaPaths: {_mp3Path}, progress: RecordedProgress());
      expect(result.filesAlreadyThere, 1);
      expect(result.filesCopied, 0);
      expect(watch.installed, isEmpty);
      expect(watch.uploads, isEmpty);
      expect(watch.commands, [_findCommand]);
    });

    test('notes what the watch refuses and goes on', () async {
      final watch = StreamingFakeWatch()
        ..installResult = const InstallResult(success: false, message: 'Image error', code: '-24')
        ..installError = ((bytes) => sameBytes(bytes, mine)
            ? const WatchException(WatchError.refused, 'The watch refused the file: No space left on device')
            : null)
        ..refusedUploads.add(_mp3Path);
      final result = await service.restore(
        watch,
        backup,
        packageIds: {'org.mine.App', 'com.samsung.weather'},
        mediaPaths: {_mp3Path},
        progress: RecordedProgress(),
      );
      expect(result.failed, [
        'My App: The watch refused the file: No space left on device',
        'Weather: the watch refused it (Image error -24)',
        '$_mp3Path: The watch refused the file: No space left on device',
      ]);
    });

    test('a lost connection ends it', () async {
      final watch = StreamingFakeWatch()
        ..shellFailures[_findCommand] = const WatchException(WatchError.lost, 'The watch stopped answering');
      await expectLater(
        service.restore(watch, backup, mediaPaths: {_mp3Path}, progress: RecordedProgress()),
        throwsA(isA<WatchException>().having((e) => e.error, 'error', WatchError.lost)),
      );
    });

    test('of a hostile backup writes only to the media folder and installs only package files', () async {
      final hostile = writeZip(dir, {
        'backup.json': encodeManifest(
          const BackupManifest(
            createdAt: '2026-10-26T11:30',
            watch: 'device::SM-R800::0',
            packages: [
              BackupPackage(
                id: 'a.b',
                name: 'Missing',
                version: '1',
                type: 'tpk',
                origin: 'downloaded',
                entry: 'packages/none.tpk',
              ),
              BackupPackage(
                id: 'c.d',
                name: 'Junk',
                version: '1',
                type: 'tpk',
                origin: 'downloaded',
                entry: '../../junk.tpk',
              ),
            ],
            media: [
              BackupMedia(path: '/etc/passwd', size: 4, entry: 'media/x'),
              BackupMedia(path: '$mediaRoot/../../../etc/passwd', size: 4, entry: 'media/x'),
              BackupMedia(path: '$mediaRoot/Music/none.mp3', size: 4, entry: 'media/none.mp3'),
              // A copy larger than its list says, as a decompression bomb would be
              BackupMedia(path: '$mediaRoot/Music/big.mp3', size: 4, entry: 'media/big'),
            ],
          ),
        ),
        'media/x': 'root',
        'media/big': 'x' * 100000,
        '../../junk.tpk': 'junk',
      });
      final watch = StreamingFakeWatch();
      final result = await service.restore(
        watch,
        hostile,
        packageIds: {'a.b', 'c.d'},
        mediaPaths: {
          '/etc/passwd',
          '$mediaRoot/../../../etc/passwd',
          '$mediaRoot/Music/none.mp3',
          '$mediaRoot/Music/big.mp3',
        },
        progress: RecordedProgress(),
      );
      expect(result.failed, [
        'Missing: its file is missing from the backup',
        'Junk: not a Tizen package (Not a valid ZIP archive)',
        '/etc/passwd: not a place for the user\'s files',
        '$mediaRoot/../../../etc/passwd: not a place for the user\'s files',
        '$mediaRoot/Music/none.mp3: missing from the backup',
        '$mediaRoot/Music/big.mp3: its copy in the backup is damaged (It is larger than 4 bytes)',
      ]);
      expect(watch.uploads, isEmpty);
      expect(watch.installed, isEmpty);
      expect(File('${dir.path}/../junk.tpk').existsSync(), isFalse);
    });
  });
}
