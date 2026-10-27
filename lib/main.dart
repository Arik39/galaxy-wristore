import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'app/watch_controller.dart';
import 'core/core.dart';
import 'demo/demo_services.dart';

/// Builds with `--dart-define=WRISTORE_DEMO=true` show a demo watch instead of looking for a real one.
const _demo = bool.fromEnvironment('WRISTORE_DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final controller = WatchController(_demo ? demoServices() : await liveServices(), prefs);
  runApp(GalaxyWristoreApp(controller: controller));
  await controller.start();
}

/// The real watch over Wi-Fi, Tizen Archive, and backups kept on this phone.
Future<Services> liveServices() async {
  final inspector = ZipPackageInspector();
  final catalog = ArchiveCatalog();
  final cache = await getApplicationCacheDirectory();
  return Services(
    connector: SdbWatchConnector(inspector: inspector),
    finder: NetworkWatchFinder(),
    catalog: catalog,
    inspector: inspector,
    backups: TwBackupService(catalog: catalog, inspector: inspector, cache: Directory('${cache.path}/packages')),
  );
}
