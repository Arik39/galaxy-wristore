import 'dart:io';
import 'dart:typed_data';

import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/catalog/archive_catalog.dart';
import 'package:galaxy_wristore/core/sdb/sdb_session.dart';
import 'package:galaxy_wristore/core/sdb/sdb_watch_connection.dart';

/// Records what a backup or restore tells its user.
class RecordedProgress implements BackupProgress {
  final List<String> steps = [];
  final List<int?> percents = [];

  @override
  void step(String text) => steps.add(text);

  @override
  void percent(int? value) => percents.add(value);
}

/// An [SdbService] that answers shell commands by their start and keeps what is pushed.
class FakeService implements SdbService {
  @override
  String get banner => 'device::SM-R800::0';

  final List<String> steps = [];
  final Map<String, String> answers = {};
  String? failOn;
  Uint8List? pushed;

  @override
  Future<String> shell(String command, {void Function(String line)? onLine}) async {
    steps.add(command);
    if (failOn != null && command.startsWith(failOn!)) throw const WatchException(WatchError.lost, 'gone');
    final out = answers.entries.where((answer) => command.startsWith(answer.key)).firstOrNull?.value ?? '';
    out.split('\n').forEach(onLine ?? (_) {});
    return out;
  }

  @override
  Future<void> push(
    String remotePath,
    Stream<List<int>> data, {
    int mode = SdbSession.defaultFileMode,
    void Function(int sent)? onProgress,
  }) async {
    steps.add('push $remotePath');
    final bytes = BytesBuilder();
    await data.forEach(bytes.add);
    pushed = bytes.takeBytes();
    onProgress?.call(pushed!.length ~/ 2);
    onProgress?.call(pushed!.length);
  }
}

/// A watch for backups and restores: shell answers by exact command, packages, files, and what it was sent.
class FakeWatch implements WatchConnection {
  FakeWatch({this.banner = 'device::SM-R800::0'});

  final String banner;
  final Map<String, String> shells = {};
  final Map<String, WatchException> shellFailures = {};
  final List<String> commands = [];
  final List<WatchPackage> packages = [];
  final Map<String, Uint8List> files = {};
  final Map<String, Uint8List> uploads = {};
  final Set<String> refusedUploads = {};
  final List<Uint8List> installed = [];
  InstallResult installResult = const InstallResult(success: true);

  /// The failure an install of a package with these bytes meets, if any.
  WatchException? Function(Uint8List package)? installError;

  @override
  WatchAddress get address => WatchAddress.parse('192.168.2.66')!;

  @override
  WatchIdentity get identity => WatchIdentity(banner: banner, model: 'SM-R800');

  @override
  Future<String> shell(String command) async {
    commands.add(command);
    final failure = shellFailures[command];
    if (failure != null) throw failure;
    return shells[command] ?? '';
  }

  @override
  Future<List<WatchPackage>> listPackages() async => List.of(packages);

  @override
  Future<WatchStatus> status() async => const WatchStatus();

  @override
  Future<InstallResult> install(File package, {void Function(InstallProgress progress)? onProgress}) async {
    final bytes = await package.readAsBytes();
    // Like the real connection, a file that is no package is refused before anything is sent
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
      throw const InvalidPackageException('Not a valid ZIP archive');
    }
    final error = installError?.call(bytes);
    if (error != null) throw error;
    onProgress?.call(Uploading(bytes.length, bytes.length));
    onProgress?.call(const Installing(100));
    installed.add(bytes);
    return installResult;
  }

  @override
  Future<InstallResult> uninstall(String packageId) async => const InstallResult(success: true);

  @override
  Future<void> upload(
    String remotePath,
    Stream<List<int>> data, {
    required int length,
    int mode = SdbSession.defaultFileMode,
    void Function(int sent)? onProgress,
  }) async {
    final bytes = BytesBuilder();
    await data.forEach(bytes.add);
    if (refusedUploads.contains(remotePath)) {
      throw const WatchException(WatchError.refused, 'The watch refused the file: No space left on device');
    }
    uploads[remotePath] = bytes.takeBytes();
    onProgress?.call(length);
  }

  @override
  Future<Uint8List> pull(String remotePath, {int maxBytes = 64 << 20, void Function(int received)? onProgress}) async {
    final bytes = files[remotePath];
    if (bytes == null) {
      throw const WatchException(WatchError.refused, 'The watch could not send the file: No such file');
    }
    onProgress?.call(bytes.length);
    return bytes;
  }

  @override
  Future<void> close() async {}
}

/// A [FakeWatch] that also streams files to disk, as the real connection does.
class StreamingFakeWatch extends FakeWatch implements StreamingPull {
  int streamedPulls = 0;

  @override
  Future<int> pullToFile(
    String remotePath,
    File target, {
    required int maxBytes,
    void Function(int received)? onProgress,
  }) async {
    final bytes = await pull(remotePath, onProgress: onProgress);
    if (bytes.length > maxBytes) throw WatchException(WatchError.refused, 'The file is larger than $maxBytes bytes');
    streamedPulls++;
    await target.writeAsBytes(bytes);
    return bytes.length;
  }
}

/// A catalog with versions and files given by the test.
class FakeCatalog implements CatalogApi {
  /// Package id to its versions, the latest first.
  final Map<String, List<VersionInfo>> versions = {};

  /// Download URL to content.
  final Map<String, Uint8List> files = {};
  final List<String> downloads = [];

  /// Thrown by every [version] call when set.
  CatalogException? failure;

  @override
  Future<VersionInfo> version(String packageId, [String? version]) async {
    if (failure != null) throw failure!;
    final known = versions[packageId] ?? const [];
    final found = version == null ? known.firstOrNull : known.where((info) => info.version == version).firstOrNull;
    return found ?? (throw const CatalogException('Not found', statusCode: 404));
  }

  @override
  Future<void> download(Artifact artifact, File target, {void Function(int received)? onProgress}) async {
    downloads.add(artifact.downloadUrl);
    final bytes = files[artifact.downloadUrl];
    if (bytes == null) throw const CatalogException('Not found', statusCode: 404);
    await target.writeAsBytes(bytes);
  }

  @override
  ArtifactChoice choose(VersionInfo info) => ArchiveCatalog().choose(info);

  @override
  Future<PackageDetails> details(String packageId) => throw UnimplementedError();

  @override
  Future<Uint8List> icon(String path) => throw UnimplementedError();

  @override
  Future<CatalogPage> search({String query = '', CatalogKind? kind, bool installableOnly = true, int page = 1}) =>
      throw UnimplementedError();
}
