import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/app/app.dart';
import 'package:galaxy_wristore/app/watch_controller.dart';
import 'package:galaxy_wristore/demo/demo_services.dart';
import 'package:galaxy_wristore/design/format.dart';
import 'package:galaxy_wristore/features/backup/restore_page.dart';
import 'package:galaxy_wristore/features/common/installed_page.dart';
import 'package:galaxy_wristore/features/watch/watch_settings_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';

void main() {
  testWidgets('the app opens on the watch, says it is a demo, and the tabs lead to each section', (tester) async {
    final root = Directory.systemTemp.createTempSync('wristore-app');
    addTearDown(() => root.deleteSync(recursive: true));
    PathProviderPlatform.instance = FakePathProvider(root);
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = WatchController(demoServices(), await SharedPreferences.getInstance());
    await tester.pumpWidget(GalaxyWristoreApp(controller: controller));
    await tester.runAsync(controller.start);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('My Watch'), findsOneWidget);
    expect(find.text('DEMO'), findsOneWidget);
    // The face on the wrist leads, and it is one the backup lacks.
    expect(find.text('GS Hybrid 7'), findsOneWidget);
    expect(find.text('ON\u00A0YOUR\u00A0WRIST · NOT\u00A0BACKED\u00A0UP', findRichText: true), findsOneWidget);
    expect(find.text('11/14'), findsOneWidget);
    expect(find.text('BACK UP 3 FACES AND APPS'), findsOneWidget);

    for (final tab in ['Faces', 'Apps', 'Backup']) {
      await tester.tap(find.byTooltip(tab));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('ADDED BY YOU · 5'), findsNothing); // the Apps page is now off stage
    expect(find.text(formatWhen(controller.backups.first.createdAt)), findsWidgets);
  });

  for (final (name, size, ratio) in [
    ('a phone on its side', const Size(2556, 1179), 3.0),
    ('a tablet', const Size(1600, 2560), 2.0),
    ('a small phone', const Size(750, 1334), 2.0),
  ]) {
    testWidgets('the watch screen lays out on $name', (tester) async {
      final root = Directory.systemTemp.createTempSync('wristore-size');
      addTearDown(() => root.deleteSync(recursive: true));
      PathProviderPlatform.instance = FakePathProvider(root);
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.reset);

      final controller = WatchController(demoServices(), await SharedPreferences.getInstance());
      await tester.pumpWidget(GalaxyWristoreApp(controller: controller));
      await tester.runAsync(controller.start);
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('My Watch'), findsOneWidget);
    });
  }

  testWidgets('every tab holds together with the largest text', (tester) async {
    final root = Directory.systemTemp.createTempSync('wristore-text');
    addTearDown(() => root.deleteSync(recursive: true));
    PathProviderPlatform.instance = FakePathProvider(root);
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final controller = WatchController(demoServices(), await SharedPreferences.getInstance());
    await tester.pumpWidget(GalaxyWristoreApp(controller: controller));
    await tester.runAsync(controller.start);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull, reason: 'Watch');

    for (final tab in ['Faces', 'Apps', 'Discover', 'Backup']) {
      await tester.tap(find.byTooltip(tab));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('Restore and a face hold together with the largest text', (tester) async {
    final root = Directory.systemTemp.createTempSync('wristore-text2');
    addTearDown(() => root.deleteSync(recursive: true));
    PathProviderPlatform.instance = FakePathProvider(root);
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final controller = WatchController(demoServices(), await SharedPreferences.getInstance());
    await tester.pumpWidget(GalaxyWristoreApp(controller: controller));
    await tester.runAsync(controller.start);
    await tester.pump(const Duration(milliseconds: 500));

    // Open the pages straight on their tabs' navigators: the layout is what is tested here, not finding the rows.
    await tester.tap(find.byTooltip('Backup'));
    await tester.pump(const Duration(milliseconds: 600));
    Navigator.of(tester.element(find.text('Backup').first))
        .push(MaterialPageRoute<void>(builder: (_) => RestorePage(record: controller.backups.first)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Restore'), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'Restore');

    await tester.tap(find.byTooltip('Faces'));
    await tester.pump(const Duration(milliseconds: 600));
    Navigator.of(tester.element(find.text('Faces').first))
        .push(MaterialPageRoute<void>(builder: (_) => InstalledPage(package: controller.faces.first)));
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull, reason: 'Face');

    await tester.tap(find.byTooltip('Watch'));
    await tester.pump(const Duration(milliseconds: 600));
    Navigator.of(tester.element(find.text('My Watch').first))
        .push(MaterialPageRoute<void>(builder: (_) => const WatchSettingsPage()));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Watch settings'), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'Watch settings');
  });
}
