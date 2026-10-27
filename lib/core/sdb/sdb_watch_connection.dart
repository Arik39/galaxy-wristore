import 'dart:io';
import 'dart:typed_data';

import '../api.dart';
import '../package/zip_package_inspector.dart';
import 'key_store.dart';
import 'sdb_key.dart';
import 'sdb_session.dart';
import 'secure_key_store.dart';
import 'watch_info.dart';
import 'watch_installer.dart';

/// A [WatchConnection] that can also stream a file from the watch straight to disk, for files too large to hold in
/// memory (music, recordings). Backups use it when the connection offers it.
abstract interface class StreamingPull {
  /// Writes the file at [remotePath] to [target] and returns its size; more than [maxBytes] is refused like by
  /// [WatchConnection.pull], and a partial [target] is deleted on failure.
  Future<int> pullToFile(
    String remotePath,
    File target, {
    required int maxBytes,
    void Function(int received)? onProgress,
  });
}

/// Opens sdb connections with the app's own key, which [keys] keeps (the platform's secure storage by default).
class SdbWatchConnector implements WatchConnector {
  /// [connectSocket] replaces `Socket.connect`, for tests.
  SdbWatchConnector({
    KeyStore? keys,
    PackageInspector? inspector,
    this.options = const SdbOptions(),
    this._connectSocket,
  }) : _keys = keys ?? SecureKeyStore(),
       _inspector = inspector ?? ZipPackageInspector();

  /// The name the watch shows when it asks its user to allow this phone.
  static const String keyName = 'GalaxyWristore@phone';

  final SdbOptions options;
  final KeyStore _keys;
  final PackageInspector _inspector;
  final SocketConnector? _connectSocket;
  Future<SdbKey>? _key;

  @override
  Future<WatchConnection> connect(
    WatchAddress address, {
    void Function()? onApprovalNeeded,
    Future<void>? giveUp,
  }) async {
    final session = await SdbSession.connect(
      host: address.host,
      port: WatchAddress.sdbPort,
      key: await _hostKey(),
      keyName: keyName,
      options: options,
      onApprovalNeeded: onApprovalNeeded,
      giveUp: giveUp,
      connectSocket: _connectSocket,
    );
    try {
      return SdbWatchConnection(
        address,
        identityFrom(session.banner, await _identityOutput(session)),
        session,
        _inspector,
      );
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  /// The key, read or made once per connector even when connections are opened at the same time.
  Future<SdbKey> _hostKey() async {
    final key = _key ??= loadOrCreateKey(_keys);
    try {
      return await key;
    } catch (_) {
      // A failure (such as a locked keychain) is not kept: the next connection tries again
      if (identical(_key, key)) _key = null;
      rethrow;
    }
  }

  static Future<String> _identityOutput(SdbSession session) async {
    try {
      return await session.shell(identityCommand);
    } on WatchException catch (error) {
      if (error.error == WatchError.lost) rethrow;
      return '';
    }
  }
}

/// A [WatchConnection] over an authorized [SdbSession].
class SdbWatchConnection implements WatchConnection, StreamingPull {
  SdbWatchConnection(this.address, this.identity, this._session, this._inspector)
    : _installer = WatchInstaller(_session);

  @override
  final WatchAddress address;
  @override
  final WatchIdentity identity;
  final SdbSession _session;
  final PackageInspector _inspector;
  final WatchInstaller _installer;

  @override
  Future<String> shell(String command) => _session.shell(command);

  @override
  Future<List<WatchPackage>> listPackages() async {
    final listed = await _installer.list();
    final origins = await _installer.origins();
    final kinds = await _installer.kinds();
    return [
      for (final package in listed)
        WatchPackage(
          id: package.id,
          name: package.name,
          version: package.version,
          type: package.type,
          origin: origins[package.id] ?? PackageOrigin.builtIn,
          kind: package.id.startsWith('com.watchface.') ? PackageKind.watchFace : kinds[package.id],
        ),
    ];
  }

  @override
  Future<WatchStatus> status() async => statusFrom(await _session.shell(statusCommand));

  /// The type is read from the package's content, not its name; a file that is no Tizen package is an
  /// [InvalidPackageException] before anything is sent.
  @override
  Future<InstallResult> install(File package, {void Function(InstallProgress progress)? onProgress}) async {
    final info = await _inspector.read(package);
    return _installer.install(package, info.type, onProgress: onProgress);
  }

  @override
  Future<InstallResult> uninstall(String packageId) => _installer.remove(packageId);

  @override
  Future<void> upload(
    String remotePath,
    Stream<List<int>> data, {
    required int length,
    int mode = SdbSession.defaultFileMode,
    void Function(int sent)? onProgress,
  }) => _session.upload(remotePath, _exactly(data, length), mode: mode, onProgress: onProgress);

  @override
  Future<Uint8List> pull(String remotePath, {int maxBytes = 64 << 20, void Function(int received)? onProgress}) async {
    final bytes = BytesBuilder(copy: false);
    await _session.pull(remotePath, bytes.add, maxBytes: maxBytes, onProgress: onProgress);
    return bytes.takeBytes();
  }

  @override
  Future<int> pullToFile(
    String remotePath,
    File target, {
    required int maxBytes,
    void Function(int received)? onProgress,
  }) async {
    final sink = target.openWrite();
    try {
      final size = await _session.pull(remotePath, sink.add, maxBytes: maxBytes, onProgress: onProgress);
      await sink.close();
      return size;
    } catch (_) {
      await sink.close().catchError((Object _) {});
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  @override
  Future<void> close() => _session.close();

  /// [data], which must be exactly [length] bytes; otherwise the upload is refused and the partial file dropped.
  static Stream<List<int>> _exactly(Stream<List<int>> data, int length) async* {
    var seen = 0;
    await for (final chunk in data) {
      seen += chunk.length;
      if (seen > length) {
        throw WatchException(WatchError.refused, 'The data is longer than the $length bytes announced');
      }
      yield chunk;
    }
    if (seen != length) {
      throw WatchException(WatchError.refused, 'The data is shorter than the $length bytes announced');
    }
  }
}
