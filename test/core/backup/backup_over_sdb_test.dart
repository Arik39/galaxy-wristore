import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/backup/backup_format.dart';
import 'package:galaxy_wristore/core/backup/tw_backup_service.dart';
import 'package:galaxy_wristore/core/package/zip_package_inspector.dart';
import 'package:galaxy_wristore/core/sdb/key_store.dart';
import 'package:galaxy_wristore/core/sdb/sdb_session.dart';
import 'package:galaxy_wristore/core/sdb/sdb_watch_connection.dart';
import 'package:galaxy_wristore/core/util/zip_reader.dart';

import '../support/fake_sdbd.dart';
import '../support/fakes.dart';
import '../support/zips.dart';

/// A backup and a restore through a real sdb connection, against the fake sdbd.
void main() {
  const mp3Path = '$mediaRoot/Music/Over the Horizon.mp3';
  const find = "find $mediaRoot -type f -printf '%s\\t%p\\n' 2>/dev/null";
  final mp3 = Uint8List.fromList(List.generate(70000, (i) => i * 13));
  final face = zipBytes({'tizen-manifest.xml': nativeManifestFor('com.watchface.GSHybrid7', '1.0.1')});

  late FakeSdbd fake;
  late Directory dir;
  late WatchConnection connection;
  late TwBackupService service;

  setUp(() async {
    fake = await FakeSdbd.start(maxData: 4096)
      ..recvFrame = 5000
      ..recvChunk = 1500
      ..shells['pkgcmd -l 2>&1'] = 'system apps\tpkg_type [tpk]\tpkgid [com.watchface.GSHybrid7]\tname [GS Hybrid 7]\tversion [1.0.1]\tstorage [internal]\n'
      ..shellsStartingWith['for p in'] = 'origin com.watchface.GSHybrid7 Preload:0 update:0\n'
      ..shells['ls -1 /opt/usr/globalapps'] = 'com.watchface.GSHybrid7\n'
      ..shells[find] = '${mp3.length}\t$mp3Path\n'
      ..files[mp3Path] = mp3;
    dir = await Directory.systemTemp.createTemp('backup-sdb-test-');
    final connector = SdbWatchConnector(
      keys: MemoryKeyStore(),
      options: const SdbOptions(readTimeout: Duration(seconds: 5), approvalTimeout: Duration(seconds: 5)),
      connectSocket: (host, port, timeout) => Socket.connect(InternetAddress.loopbackIPv4, fake.port, timeout: timeout),
    );
    connection = await connector.connect(WatchAddress.parse('192.168.2.66')!);
    final catalog = FakeCatalog()
      ..versions['com.watchface.GSHybrid7'] = [
        VersionInfo(
          id: 'com.watchface.GSHybrid7',
          version: '1.0.1',
          artifacts: [
            Artifact(
              downloadUrl: '/api/f',
              sha256: sha256.convert(face).toString(),
              size: face.length,
              verdict: Verdict.installable,
            ),
          ],
          buildVerdicts: const [Verdict.installable],
        ),
      ]
      ..files['/api/f'] = face;
    service = TwBackupService(
      catalog: catalog,
      inspector: ZipPackageInspector(),
      cache: Directory('${dir.path}/cache'),
    );
  });
  tearDown(() async {
    await connection.close();
    await fake.close();
    await dir.delete(recursive: true);
  });

  test('a backup reads the watch over sdb, and a restore puts its file back', () async {
    final backup = await service.create(connection, Directory('${dir.path}/out'), progress: RecordedProgress());
    final zip = ZipReader.open(backup.path);
    addTearDown(zip.close);
    final manifest = readManifest(zip);
    expect(manifest.watch, 'device::SM-R800::0');
    expect(manifest.packages.single.entry, isNotNull);
    expect(manifest.media.single.size, mp3.length);
    expect(zip.read(zip['media/Music/Over the Horizon.mp3']!, maxBytes: 1 << 20), mp3);

    // The watch was reset: the file is gone, the face came back from somewhere else
    fake
      ..files.remove(mp3Path)
      ..shells[find] = '';
    final result = await service.restore(
      connection,
      backup,
      packageIds: {'com.watchface.GSHybrid7'},
      mediaPaths: {mp3Path},
      progress: RecordedProgress(),
    );
    expect(result.alreadyThere, ['GS Hybrid 7']);
    expect(result.filesCopied, 1);
    expect(result.failed, isEmpty);
    expect(fake.files[mp3Path], mp3);
    expect(fake.modes[mp3Path], 420);
  });
}
