import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/sdb/watch_installer.dart';

import '../support/fakes.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('installer-test-'));
  tearDown(() => dir.delete(recursive: true));

  File packageFile([List<int>? content]) =>
      File('${dir.path}/x.wgt')..writeAsBytesSync(content ?? List.generate(5000, (i) => i & 0xff));

  const ok =
      'key[install_percent] val[40]\nkey[install_percent] val[90]\nkey[end] val[ok]\nspend time for pkgcmd is [4000]ms';

  test('origins come from the package manager\'s preload and update flags', () async {
    final service = FakeService()
      ..answers['for p in'] =
          'origin com.samsung.weather Preload:1 update:1 \r\n'
          'origin com.samsung.alarm-solis Preload:1 update:0 \n'
          'origin 2048abcdeg Preload:0 update:0\n'
          'some noise\n'
          'origin bad;id Preload:1 update:0\n'
          'origin .. Preload:0 update:0\n';
    expect(await WatchInstaller(service).origins(), {
      'com.samsung.weather': PackageOrigin.builtInUpdated,
      'com.samsung.alarm-solis': PackageOrigin.builtIn,
      '2048abcdeg': PackageOrigin.downloaded,
    });
    // One constant command; nothing from the watch goes back into a command
    expect(service.steps, hasLength(1));
    expect(service.steps.single, startsWith(r'for p in $(ls -1 /opt/usr/globalapps); do'));
  });

  test('kinds come from the manifests the shell can read', () async {
    final service = FakeService()
      ..answers['grep'] =
          '/opt/usr/globalapps/com.watchface.GSHybrid7/tizen-manifest.xml:1\n'
          '/opt/usr/globalapps/org.pekdemir.TetriS2/tizen-manifest.xml:0\r\n'
          '/opt/usr/globalapps/55V5m8QGTw/res/wgt/config.xml:2\n'
          '/usr/apps/com.samsung.clock/tizen-manifest.xml:0\n'
          '/opt/usr/globalapps/com.samsung.clock/tizen-manifest.xml:1\n'
          '/opt/usr/globalapps/a;b/tizen-manifest.xml:1\n'
          '/etc/passwd:1\n';
    expect(await WatchInstaller(service).kinds(), {
      'com.watchface.GSHybrid7': PackageKind.watchFace,
      'org.pekdemir.TetriS2': PackageKind.app,
      '55V5m8QGTw': PackageKind.watchFace,
      'com.samsung.clock': PackageKind.watchFace,
    });
    expect(service.steps.single, startsWith('grep -H -c '));
  });

  test('an install makes the directory, uploads, installs and cleans up', () async {
    final service = FakeService()..answers['pkgcmd -i'] = ok;
    final file = packageFile();
    final sha = sha256.convert(file.readAsBytesSync()).toString();
    final events = <InstallProgress>[];
    final result = await WatchInstaller(service).install(file, 'wgt', onProgress: events.add);

    expect(result.success, isTrue);
    final remote = '/home/owner/share/tmp/sdk_tools/${sha.substring(0, 16)}.wgt';
    final hex16 = '[0-9a-f]' * 16;
    expect(service.steps, [
      'mkdir -p /home/owner/share/tmp/sdk_tools; rm -f /home/owner/share/tmp/sdk_tools/$hex16.wgt /home/owner/share/tmp/sdk_tools/$hex16.tpk',
      'push $remote',
      'pkgcmd -i -t wgt -p $remote -w 2>&1',
      'rm -f $remote',
    ]);
    expect(service.pushed, file.readAsBytesSync());
    final uploads = events.whereType<Uploading>().toList();
    expect(uploads.map((event) => event.sent), [2500, 5000]);
    expect(uploads.every((event) => event.total == 5000), isTrue);
    expect(events.whereType<Installing>().map((event) => event.percent), [null, 40, 90]);
  });

  test('a tpk goes through the same steps with its own type', () async {
    final service = FakeService()..answers['pkgcmd -i'] = ok;
    await WatchInstaller(service).install(File('${dir.path}/y.tpk')..writeAsBytesSync(Uint8List(10)), 'tpk');
    expect(
      service.steps.any((step) => step.startsWith('pkgcmd -i -t tpk -p ') && step.endsWith('.tpk -w 2>&1')),
      isTrue,
    );
  });

  test('a refusal is returned and the file is still removed', () async {
    final service = FakeService()
      ..answers['pkgcmd -i'] = 'key[error] val[-24]\nkey[end] val[fail]\nprocessing result : Image error [-24] failed';
    final result = await WatchInstaller(service).install(packageFile(), 'wgt');
    expect(result.success, isFalse);
    expect(result.code, '-24');
    expect(result.message, 'Image error');
    expect(service.steps.last, startsWith('rm -f '));
  });

  test('a lost connection during the install is raised, cleanup does not hide it', () async {
    final service = FakeService()..failOn = 'pkgcmd -i';
    await expectLater(
      WatchInstaller(service).install(packageFile(), 'wgt'),
      throwsA(isA<WatchException>().having((e) => e.error, 'error', WatchError.lost)),
    );
    expect(service.steps.last, startsWith('rm -f '), reason: 'cleanup was tried');
  });

  test('the remote name and the commands contain only safe characters', () async {
    final service = FakeService()..answers['pkgcmd -i'] = ok;
    final evil = File('${dir.path}/evil name; rm -rf %2F\$(id).wgt')..writeAsBytesSync(Uint8List(10));
    await WatchInstaller(service).install(evil, 'wgt');
    for (final step in service.steps) {
      expect(RegExp(r'^[A-Za-z0-9 /._:>&=;\[\]-]+$').hasMatch(step), isTrue, reason: step);
    }
  });

  test('an empty package is refused before anything is sent', () async {
    final service = FakeService();
    await expectLater(
      WatchInstaller(service).install(packageFile(const []), 'wgt'),
      throwsA(isA<InvalidPackageException>()),
    );
    expect(service.steps, isEmpty);
  });

  test('list reads the lines of pkgcmd -l', () async {
    final service = FakeService()
      ..answers['pkgcmd -l'] = [
        'system apps\tpkg_type [wgt]\tpkgid [55V5m8QGTw]\tname [White Light]\tversion [1.0.4]\tstorage [internal]',
        'system apps\tpkg_type [tpk]\tpkgid [com.samsung.w-music-player]\tname [Музыка]\tversion [2.4.56]\tstorage [internal]',
        'system apps\tpkg_type [tpk]\tpkgid [com.x]\tname [A [beta] app]\tversion [1.0]\tstorage [internal]',
        'system apps\tpkg_type [tpk]\tpkgid [com.y]\tname [\u0007\u0001 ]\tversion [1.0]\tstorage [internal]',
        'spend time for pkgcmd is [10]ms',
        '',
      ].join('\n');
    final packages = await WatchInstaller(service).list();
    expect(packages.map((package) => package.id), ['55V5m8QGTw', 'com.samsung.w-music-player', 'com.x', 'com.y']);
    expect(packages.map((package) => package.name), ['White Light', 'Музыка', 'A [beta] app', 'com.y']);
    expect(packages.map((package) => package.version), ['1.0.4', '2.4.56', '1.0', '1.0']);
    expect(packages.map((package) => package.type), ['wgt', 'tpk', 'tpk', 'tpk']);
  });

  test('remove runs one fixed command for a valid id', () async {
    final service = FakeService()..answers['pkgcmd -u'] = 'key[end] val[ok]';
    expect((await WatchInstaller(service).remove('com.example.App-1')).success, isTrue);
    expect(service.steps, ['pkgcmd -u -n com.example.App-1 2>&1']);
  });

  test('remove refuses ids that could be options or commands', () async {
    final service = FakeService();
    final installer = WatchInstaller(service);
    for (final id in [
      '',
      '-a',
      'a b',
      'a;rm',
      r'a$(id)',
      'a`id`',
      'a\nb',
      'a|b',
      'a&b',
      'a/b',
      "'a'",
      'a' * 129,
      '..',
    ]) {
      await expectLater(
        installer.remove(id),
        throwsA(isA<WatchException>().having((e) => e.error, 'error', WatchError.refused)),
        reason: "'$id'",
      );
    }
    expect(service.steps, isEmpty);
    expect(WatchInstaller.isPackageId('a' * 128), isTrue);
  });
}
