import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/app/services.dart';
import 'package:galaxy_wristore/app/watch_controller.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/demo/demo_services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';

class _FailingConnector implements WatchConnector {
  _FailingConnector(this.error);

  final WatchError error;

  @override
  Future<WatchConnection> connect(
    WatchAddress address, {
    void Function()? onApprovalNeeded,
    Future<void>? giveUp,
  }) async => throw WatchException(error, 'test');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wristore-test');
    PathProviderPlatform.instance = FakePathProvider(root);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('the demo watch: what is on it, what a reset would lose, the face on the wrist', () async {
    final c = WatchController(demoServices(), await SharedPreferences.getInstance());
    await c.start();
    expect(c.phase, LinkPhase.connected);
    expect(c.problem, isNull);
    expect(c.faces, hasLength(9));
    expect(c.downloaded, hasLength(14));
    expect([for (final p in c.notBackedUp) p.name], ['GS Hybrid 7', 'GS Hybrid 6', 'MD210']);
    expect(c.backedUpCount, 11);
    expect(c.currentFaceId, 'com.watchface.GSHybrid7');
    expect(c.pictureOf('com.watchface.GSHybrid7'), isNotNull);
    expect(c.operation, isNull);
  });

  test('every way the watch can fail ends in its own state and one next step', () async {
    final prefs = await SharedPreferences.getInstance();
    final demo = demoServices();
    final cases = {
      WatchError.unreachable: (LinkPhase.unreachable, 'same Wi-Fi'),
      WatchError.notAnswering: (LinkPhase.notAnswering, 'Debugging'),
      WatchError.busy: (LinkPhase.busy, 'Another device'),
      WatchError.approvalTimeout: (LinkPhase.failed, 'check mark'),
      WatchError.lost: (LinkPhase.failed, 'broke'),
    };
    for (final MapEntry(key: error, value: (phase, words)) in cases.entries) {
      final services = Services(
        connector: _FailingConnector(error),
        finder: demo.finder,
        catalog: demo.catalog,
        inspector: demo.inspector,
        backups: demo.backups,
      );
      final c = WatchController(services, prefs);
      await c.setAddress(WatchAddress.parse('192.168.2.66')!);
      expect(c.phase, phase, reason: '$error');
      expect(c.problem, contains(words), reason: '$error');
      expect(c.operation, isNull, reason: '$error');
    }
  });

  test('the address is remembered, and only a private one is taken', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = WatchController(demoServices(), prefs);
    await c.setAddress(WatchAddress.parse('10.0.0.42')!);
    expect(prefs.getString('watch.address'), '10.0.0.42');
    expect(WatchAddress.parse('8.8.8.8'), isNull);
    expect(WatchAddress.parse('192.168.1.255'), isNull);
    expect(WatchAddress.parse('192.168.1.300'), isNull);
    expect(WatchAddress.parse(' 172.16.5.4 ')?.host, '172.16.5.4');
  });

  test('a package with no reported kind is a face when its id says so', () {
    WatchPackage p(String id) => WatchPackage(id: id, name: id, version: '1', type: 'tpk');
    expect(WatchController.kindOf(p('com.watchface.GSHybrid6')), PackageKind.watchFace);
    expect(WatchController.kindOf(p('org.pekdemir.TetriS2')), PackageKind.app);
  });

  test('an update from Tizen Archive reaches the watch, and the watch lists the new version', () async {
    final c = WatchController(demoServices(), await SharedPreferences.getInstance());
    await c.start();
    expect(c.packages.firstWhere((p) => p.id == 'com.watchface.GSHybrid7').version, '1.0.1');
    final latest = (await c.services.catalog.details('com.watchface.GSHybrid7')).latestVersion;
    expect(latest, '1.0.2');

    final failure = await c.installFromCatalog('com.watchface.GSHybrid7', 'GS Hybrid 7');
    expect(failure, isNull);
    expect(c.packages.firstWhere((p) => p.id == 'com.watchface.GSHybrid7').version, '1.0.2');
    expect(c.operation, isNull);
    expect(c.job, isNull);
  });

  test('a package Tizen Archive does not have is reported as missing, not as another package', () async {
    final c = WatchController(demoServices(), await SharedPreferences.getInstance());
    await expectLater(
      c.services.catalog.details('com.watchface.MessaRT18'),
      throwsA(isA<CatalogException>().having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('ringing the watch plays its find tone until it is stopped, and opening one of its screens works', () async {
    final c = WatchController(demoServices(), await SharedPreferences.getInstance());
    await c.start();
    expect(c.currentFaceId, 'com.watchface.GSHybrid7');

    final ringing = c.ring();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(c.ringing, isTrue);
    expect(c.operation?.label, 'Ringing your watch');
    c.stopRinging();
    await ringing;
    expect(c.ringing, isFalse);
    expect(c.operation, isNull);
    expect(c.problem, isNull);

    expect(await c.openOnWatch('com.samsung.clocksetting.sound'), isNull);
    expect(await c.openOnWatch('rm -rf /'), isNotNull);
  });

  test('asking again drops the connection waiting for approval and makes the watch ask again', () async {
    final c = WatchController(demoServices(), await SharedPreferences.getInstance());
    final connecting = c.setAddress(WatchAddress.parse('192.168.2.66')!);
    while (c.phase != LinkPhase.waitingForApproval) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(c.askedTimes, 1);
    c.askAgain();
    while (c.askedTimes < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(c.phase, LinkPhase.waitingForApproval);
    await connecting;
    expect(c.phase, LinkPhase.connected);
    expect(c.problem, isNull);
  });

  test('a backup saves what Tizen Archive has, and what it does not have is not offered again', () async {
    final c = WatchController(demoServices(), await SharedPreferences.getInstance());
    await c.start();
    expect([for (final p in c.toBackUp) p.name], ['GS Hybrid 7', 'GS Hybrid 6', 'MD210']);
    expect(c.unsaveable, isEmpty);

    await c.backUp();
    expect(c.latestBackup!.idsUnsaveable, {'com.watchface.MD210'});
    expect([for (final p in c.notBackedUp) p.name], ['MD210']);
    expect([for (final p in c.unsaveable) p.name], ['MD210']);
    expect(c.toBackUp, isEmpty);
    expect(c.backedUpCount, 13);
  });

  test('a backup stopped halfway keeps nothing and leaves the watch connected', () async {
    final c = WatchController(demoServices(), await SharedPreferences.getInstance());
    await c.start();
    final before = c.backups.length;

    final running = c.backUp();
    while (c.job != Job.backingUp || (c.operation?.progress ?? -1) <= 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    c.stopBackUp();
    expect(c.stopping, isTrue);
    expect(await running, isNull);
    expect(c.wasStopped, isTrue);
    expect(c.problem, isNull);
    expect(c.backups, hasLength(before));
    expect(c.job, isNull);
    expect(c.stopping, isFalse);
    expect(c.phase, LinkPhase.connected);
  });
}
