import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// App folders in a temporary directory, so tests never touch a real phone's files.
class FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  FakePathProvider(this.root);

  final Directory root;

  String _dir(String name) {
    final d = Directory('${root.path}/$name')..createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');

  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');

  @override
  Future<String?> getTemporaryPath() async => _dir('temp');
}
