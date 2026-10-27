import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/sdb/key_store.dart';
import 'package:galaxy_wristore/core/sdb/sdb_session.dart';
import 'package:galaxy_wristore/core/sdb/sdb_watch_connection.dart';
import 'package:galaxy_wristore/core/sdb/watch_info.dart';

import '../support/fake_sdbd.dart';
import '../support/zips.dart';

class _FlakyStore implements KeyStore {
  final MemoryKeyStore _inner = MemoryKeyStore();
  var failures = 1;

  @override
  Future<String?> read() async {
    if (failures-- > 0) throw StateError('keychain locked');
    return _inner.read();
  }

  @override
  Future<void> write(String pem) => _inner.write(pem);
}

Matcher _fails(WatchError error) => throwsA(isA<WatchException>().having((e) => e.error, 'error', error));

void main() {
  final address = WatchAddress.parse('192.168.2.66')!;
  late FakeSdbd fake;
  late Directory dir;

  setUp(() async {
    fake = await FakeSdbd.start();
    dir = await Directory.systemTemp.createTemp('connection-test-');
  });
  tearDown(() async {
    await fake.close();
    await dir.delete(recursive: true);
  });

  SdbWatchConnector connector(KeyStore keys) => SdbWatchConnector(
    keys: keys,
    options: const SdbOptions(readTimeout: Duration(seconds: 5), approvalTimeout: Duration(seconds: 5)),
    // Whatever the address, the fake on loopback answers
    connectSocket: (host, port, timeout) {
      expect([host, port], ['192.168.2.66', WatchAddress.sdbPort]);
      return Socket.connect(InternetAddress.loopbackIPv4, fake.port, timeout: timeout);
    },
  );

  Future<WatchConnection> connect([KeyStore? keys]) async {
    final connection = await connector(keys ?? MemoryKeyStore()).connect(address);
    addTearDown(connection.close);
    return connection;
  }

  test(
    'a first connection asks the watch to allow the phone once, with the app\'s key name, and keeps the key',
    () async {
      fake.shells[identityCommand] = '<key name="tizen.org/feature/platform.version" type="string">5.5.0</key>';
      final keys = MemoryKeyStore();
      var asked = 0;
      final first = await connector(keys).connect(address, onApprovalNeeded: () => asked++);
      addTearDown(first.close);
      expect(asked, 1);
      expect(fake.keyNames, [SdbWatchConnector.keyName]);
      expect(first.address, address);
      expect(first.identity.banner, 'device::SM-R800::0');
      expect(first.identity.model, 'SM-R800');
      expect(first.identity.tizenVersion, '5.5');
      expect(first.identity.name, 'Galaxy Watch 46 mm');
      await first.close();

      // Another connector with the same store uses the same key: the watch does not ask again
      final second = await connector(keys).connect(address, onApprovalNeeded: () => asked++);
      addTearDown(second.close);
      expect(asked, 1);
      expect(fake.confirmations, 1);
    },
  );

  test('a key store that fails is not remembered as failed', () async {
    final flaky = connector(_FlakyStore());
    await expectLater(flaky.connect(address), throwsStateError);
    final connection = await flaky.connect(address);
    addTearDown(connection.close);
    expect(connection.identity.model, 'SM-R800');
  });

  test('the package list says where each package came from and what it is', () async {
    fake
      ..shells['pkgcmd -l 2>&1'] = [
        'system apps\tpkg_type [wgt]\tpkgid [55V5m8QGTw]\tname [White Light]\tversion [1.0.4]\tstorage [internal]',
        'system apps\tpkg_type [tpk]\tpkgid [com.watchface.GSHybrid7]\tname [GS Hybrid 7]\tversion [1.0.1]\tstorage [internal]',
        'system apps\tpkg_type [tpk]\tpkgid [com.samsung.weather]\tname [Weather]\tversion [2.0]\tstorage [internal]',
        'system apps\tpkg_type [tpk]\tpkgid [com.samsung.clock]\tname [Clock]\tversion [1.0]\tstorage [internal]',
      ].join('\n')
      ..shellsStartingWith['for p in'] =
          'origin 55V5m8QGTw Preload:0 update:0\n'
          'origin com.watchface.GSHybrid7 Preload:0 update:0\n'
          'origin com.samsung.weather Preload:1 update:1\n'
      ..shellsStartingWith['grep -H -c'] =
          '/opt/usr/globalapps/55V5m8QGTw/res/wgt/config.xml:0\n'
          '/opt/usr/globalapps/com.samsung.weather/tizen-manifest.xml:0\n';
    final packages = {for (final package in await (await connect()).listPackages()) package.id: package};
    expect(packages.keys, ['55V5m8QGTw', 'com.watchface.GSHybrid7', 'com.samsung.weather', 'com.samsung.clock']);
    expect(packages.values.map((package) => package.origin), [
      PackageOrigin.downloaded,
      PackageOrigin.downloaded,
      PackageOrigin.builtInUpdated,
      PackageOrigin.builtIn,
    ]);
    expect(packages.values.map((package) => package.kind), [
      PackageKind.app,
      PackageKind.watchFace,
      PackageKind.app,
      null,
    ]);
    expect(packages['55V5m8QGTw']!.type, 'wgt');
    expect(packages['com.samsung.weather']!.name, 'Weather');
  });

  test('status reads battery and storage', () async {
    fake.shells[statusCommand] =
        'capacity=64\nstatus=Discharging\nFilesystem 1K-blocks Used Available Use% Mounted on\n'
        '/dev/mmcblk0p20 1000 400 600 40% /opt/usr\n';
    final status = await (await connect()).status();
    expect(
      [status.batteryPercent, status.charging, status.storageFreeBytes, status.storageTotalBytes],
      [64, false, 600 * 1024, 1000 * 1024],
    );
  });

  test('an install sends the package under a neutral name, installs it with pkgcmd -w and cleans up', () async {
    final package = writeZip(dir, {'tizen-manifest.xml': tpkManifest, 'bin/face': 'x' * 3000}, name: 'my face (1).tpk');
    final remote =
        '/home/owner/share/tmp/sdk_tools/${sha256.convert(package.readAsBytesSync()).toString().substring(0, 16)}.tpk';
    fake.shells['pkgcmd -i -t tpk -p $remote -w 2>&1'] =
        'key[install_percent] val[50]\nkey[install_percent] val[100]\nkey[end] val[ok]\n';
    final events = <InstallProgress>[];
    final result = await (await connect()).install(package, onProgress: events.add);
    expect(result.success, isTrue);
    expect(fake.files[remote], package.readAsBytesSync());
    expect(fake.commands.last, 'rm -f $remote');
    expect(events.whereType<Uploading>().last.sent, package.lengthSync());
    expect(events.whereType<Installing>().map((event) => event.percent), [null, 50, 100]);
  });

  test('a file that is no Tizen package is refused before anything is sent', () async {
    final notAPackage = File('${dir.path}/x.tpk')..writeAsStringSync('hello');
    final connection = await connect();
    final before = List.of(fake.commands);
    await expectLater(connection.install(notAPackage), throwsA(isA<InvalidPackageException>()));
    expect(fake.commands, before);
    expect(fake.files, isEmpty);
  });

  test('uninstall runs pkgcmd -u for a package id and refuses anything else', () async {
    fake.shells['pkgcmd -u -n com.example.App 2>&1'] = 'key[end] val[ok]';
    final connection = await connect();
    expect((await connection.uninstall('com.example.App')).success, isTrue);
    await expectLater(connection.uninstall('-rf /'), _fails(WatchError.refused));
    expect(fake.commands.where((command) => command.startsWith('pkgcmd -u')), ['pkgcmd -u -n com.example.App 2>&1']);
  });

  test('files go to the watch only in full, and come back in memory or to disk', () async {
    const path = '/opt/usr/home/owner/media/Music/Song One.mp3';
    final data = Uint8List.fromList(List.generate(40000, (i) => i * 3));
    final connection = await connect();
    final sent = <int>[];
    await connection.upload(path, Stream.value(data), length: data.length, onProgress: sent.add);
    expect(fake.files[path], data);
    expect(sent.last, data.length);

    await expectLater(
      connection.upload('$path.long', Stream.value(data), length: data.length - 1),
      _fails(WatchError.refused),
    );
    await expectLater(
      connection.upload('$path.short', Stream.value(data), length: data.length + 1),
      _fails(WatchError.refused),
    );
    expect(fake.files.keys, [path]);

    expect(await connection.pull(path), data);
    await expectLater(connection.pull(path, maxBytes: 100), _fails(WatchError.refused));
    final streaming = connection as StreamingPull;
    final target = File('${dir.path}/song.mp3');
    expect(await streaming.pullToFile(path, target, maxBytes: data.length), data.length);
    expect(target.readAsBytesSync(), data);
    for (final (source, limit) in [('/opt/usr/home/owner/media/missing.mp3', 1 << 20), (path, data.length - 1)]) {
      final partial = File('${dir.path}/partial');
      await expectLater(streaming.pullToFile(source, partial, maxBytes: limit), _fails(WatchError.refused));
      expect(partial.existsSync(), isFalse, reason: 'nothing is left of a refused file');
    }
  });

  test('a file the watch cannot write is refused at once, with its reason, and the connection goes on', () async {
    const path = '/opt/usr/home/owner/media/locked.mp3';
    fake
      ..failAtSend.add(path)
      ..shells['echo ok'] = 'ok\n';
    final connection = await connect();
    final data = Uint8List(100000);
    await expectLater(
      connection.upload(path, Stream.value(data), length: data.length),
      throwsA(
        isA<WatchException>()
            .having((e) => e.error, 'error', WatchError.refused)
            .having((e) => e.message, 'message', contains('Permission denied')),
      ),
    );
    expect(fake.files.containsKey(path), isFalse);
    expect(await connection.shell('echo ok'), 'ok\n');
  });

  test('a closed connection fails as lost', () async {
    final connection = await connect();
    await connection.close();
    await expectLater(connection.shell('true'), _fails(WatchError.lost));
  });
}
