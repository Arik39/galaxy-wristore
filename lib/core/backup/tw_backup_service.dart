import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import '../api.dart';
import '../catalog/archive_catalog.dart';
import '../sdb/sdb_watch_connection.dart';
import '../sdb/watch_installer.dart';
import '../util/hashing.dart';
import '../util/mime_base64.dart';
import 'backup_archive.dart';
import 'backup_format.dart';
import 'fingerprint_tar.dart';
import 'zip_backup_contents.dart';

/// Backups in the `.twbackup` format the Mac app also reads and writes.
///
/// A backup saves everything a reset erases that can be saved: copies of the apps and watch faces downloaded to the
/// watch (the user's own package files first, then Tizen Archive's), the user's files on the watch, and a fingerprint
/// of every app (what the watch lets be read of it, and the certificate database). The data inside apps cannot be
/// read, so it is not in the backup.
class TwBackupService implements BackupService {
  /// [cache] keeps Tizen Archive's files between backups, by SHA-256, so a new backup does not fetch everything again
  /// (a folder in the system's temporary space by default, which the system may empty); [clock] tells the time a
  /// backup is made.
  TwBackupService({required this._catalog, required this._inspector, Directory? cache, DateTime Function()? clock})
    : _cache = cache ?? Directory('${Directory.systemTemp.path}/wristore-package-cache'),
      _clock = clock ?? DateTime.now;

  final CatalogApi _catalog;
  final PackageInspector _inspector;
  final Directory _cache;
  final DateTime Function() _clock;

  static const String _globalApps = '/opt/usr/globalapps';
  static final RegExp _sha256 = RegExp(r'^[0-9a-fA-F]{64}$');

  @override
  Future<File> create(
    WatchConnection watch,
    Directory folder, {
    Directory? extraPackages,
    required BackupProgress progress,
  }) async {
    final work = await Directory.systemTemp.createTemp('wristore-backup-');
    // Downloads arrive beside the work folder, so that a broken one never ends up in the backup
    final download = File('${work.path}.download');
    try {
      final snapshot = await _readWatch(watch, work, progress);
      // The watch is not needed for the rest
      final extras = await _ownPackages(extraPackages);
      final packages = <BackupPackage>[];
      for (final (n, package) in snapshot.packages.indexed) {
        progress
          ..step('Copy ${n + 1} of ${snapshot.packages.length}: ${package.name}')
          ..percent(n * 100 ~/ snapshot.packages.length);
        packages.add(await _packageCopy(package, work, download, extras));
      }
      progress
        ..step('Writing the backup file…')
        ..percent(-1);
      return await _write(folder, snapshot, packages, work);
    } finally {
      await work.delete(recursive: true);
      if (await download.exists()) await download.delete();
    }
  }

  @override
  Future<BackupContents> open(File backup) async {
    final path = backup.path;
    final (manifest, items) = await Isolate.run(() => readBackupIndex(path));
    return ZipBackupContents(backup, manifest, items, _inspector);
  }

  /// Puts back what was chosen, packages first. A package the watch refuses, or a file it will not take, is noted in
  /// the result and the restore goes on; a lost connection ends it.
  @override
  Future<RestoreResult> restore(
    WatchConnection watch,
    File backup, {
    Set<String> packageIds = const {},
    Set<String> mediaPaths = const {},
    required BackupProgress progress,
  }) async {
    final path = backup.path;
    final (manifest, entries) = await Isolate.run(() => readBackupManifest(path));
    final result = RestoreResult();
    final temp = await Directory.systemTemp.createTemp('wristore-restore-');
    try {
      if (packageIds.isNotEmpty) {
        final chosen = [
          for (final package in manifest.packages)
            if (packageIds.contains(package.id)) package,
        ];
        await _installAll(watch, path, chosen, entries, temp, result, progress);
      }
      if (mediaPaths.isNotEmpty) {
        final chosen = [
          for (final media in manifest.media)
            if (mediaPaths.contains(media.path)) media,
        ];
        await _copyBack(watch, path, chosen, entries, temp, result, progress);
      }
    } finally {
      await temp.delete(recursive: true);
    }
    return result;
  }

  Future<_Snapshot> _readWatch(WatchConnection watch, Directory work, BackupProgress progress) async {
    progress
      ..step('Reading the packages on the watch…')
      ..percent(-1);
    final listed = {for (final package in await watch.listPackages()) package.id: package};
    // Only plain package ids go into a command on the watch
    final ids = [
      for (final line in (await watch.shell('ls -1 $_globalApps')).split('\n'))
        if (WatchInstaller.isPackageId(line.trim())) line.trim(),
    ];
    final fingerprints = '${work.path}/fingerprints';
    for (final (n, id) in ids.indexed) {
      progress
        ..step('Fingerprint ${n + 1} of ${ids.length}: ${listed[id]?.name ?? id}')
        ..percent(n * 100 ~/ ids.length);
      final directory = await Directory('$fingerprints/$id').create(recursive: true);
      final pkginfo = await watch.shell('pkginfo --pkg $id 2>&1');
      await File('${directory.path}/pkginfo.txt').writeAsString(pkginfo.replaceAll('\r', ''));
      await _readableFiles(watch, id, directory);
    }
    // The certificates every installed package was signed with, .wgt ones included
    final certificates = await Directory('$fingerprints/_certificate-database').create(recursive: true);
    for (final name in const ['.pkgmgr_cert.db', '.pkgmgr_cert.db-journal']) {
      try {
        final bytes = decodeMimeBase64(await watch.shell('base64 /opt/dbspace/$name 2>/dev/null'));
        if (bytes.isNotEmpty) await File('${certificates.path}/${name.substring(1)}').writeAsBytes(bytes);
      } on FormatException {
        // Not Base64: left out
      } on WatchException catch (error) {
        if (error.error != WatchError.protocol) rethrow;
        // Too large to read through the shell: left out
      }
    }
    final media = await _readMedia(watch, work, progress);
    final packages = [
      for (final id in ids)
        if (listed[id] case final package? when (package.origin ?? PackageOrigin.builtIn) != PackageOrigin.builtIn)
          _WatchedPackage(id, package.name, package.version, package.type, package.origin!),
    ];
    return _Snapshot(watch.identity.banner, packages, media);
  }

  /// What the watch lets be read of an app: its manifest, signatures and shared resources, sent as a tar in Base64.
  Future<void> _readableFiles(WatchConnection watch, String id, Directory directory) async {
    final String archive;
    try {
      archive = await watch.shell(
        'cd $_globalApps/$id && tar -cf - --exclude=locale tizen-manifest.xml '
        'author-signature.xml signature1.xml signature2.xml shared/res 2>/dev/null | base64',
      );
    } on WatchException catch (error) {
      if (error.error != WatchError.protocol) rethrow;
      await File('${directory.path}/skipped.txt')
          .writeAsString('Its readable files were too large to read: ${error.message}\n');
      return;
    }
    try {
      unpackFingerprint(decodeMimeBase64(archive), directory.path);
    } on FormatException catch (error) {
      await File('${directory.path}/skipped.txt')
          .writeAsString('Its readable files could not be read: ${error.message}\n');
    }
  }

  /// The user's files, byte for byte; hidden folders (the watch's own logs) stay out, and a file the watch will not
  /// send is left out.
  Future<List<BackupMedia>> _readMedia(WatchConnection watch, Directory work, BackupProgress progress) async {
    final files = (await remoteMedia(watch)).entries.toList();
    final media = <BackupMedia>[];
    for (final (n, MapEntry(key: path, value: size)) in files.indexed) {
      final relative = mediaRelative(path)!;
      progress.step('File ${n + 1} of ${files.length}: $relative');
      final target = File('${work.path}/media/$relative');
      await target.parent.create(recursive: true);
      void onProgress(int done) => progress.percent(size > 0 ? min(100, done * 100 ~/ size) : -1);
      // A file may grow a little between the listing and the copy (a recording in progress), but not without end
      final limit = size + (64 << 20);
      try {
        if (watch is StreamingPull) {
          await (watch as StreamingPull).pullToFile(path, target, maxBytes: limit, onProgress: onProgress);
        } else {
          await target.writeAsBytes(await watch.pull(path, maxBytes: limit, onProgress: onProgress));
        }
      } on WatchException catch (error) {
        if (error.error != WatchError.refused) rethrow;
        progress.step('$relative could not be read: ${error.message}');
        continue;
      }
      media.add(BackupMedia(path: path, size: await target.length(), entry: 'media/$relative'));
    }
    return media;
  }

  /// The user's own file for [package] first (the version on the watch preferred), then Tizen Archive's copy.
  Future<BackupPackage> _packageCopy(
    _WatchedPackage package,
    Directory work,
    File download,
    List<(File, TizenPackageInfo)> extras,
  ) async {
    BackupPackage copy({String? entry, String? entryVersion, String? source, String? note}) => BackupPackage(
      id: package.id,
      name: package.name,
      version: package.version,
      type: package.type,
      origin: originName(package.origin),
      entry: entry,
      entryVersion: entryVersion,
      source: source,
      note: note,
    );

    final own = extras.where((extra) => extra.$2.packageId == package.id);
    final chosen = own.where((extra) => extra.$2.version == package.version).firstOrNull ?? own.firstOrNull;
    if (chosen != null) {
      final (file, info) = chosen;
      final entry =
          'packages/${safeFileName('${package.name} (${package.id}) v${info.version ?? 'unknown'}', info.type)}';
      await Directory('${work.path}/packages').create(recursive: true);
      await file.copy('${work.path}/$entry');
      final storeSigned = await _inspector.signature(file) == SignatureVerdict.storeSigned;
      return copy(
        entry: entry,
        entryVersion: info.version,
        source: 'your file ${file.uri.pathSegments.last}',
        note: storeSigned ? null : 'This file is not store-signed: the watch may refuse it.',
      );
    }
    if (!isCatalogIdentifier(package.id)) return copy(note: 'Not in Tizen Archive: a reset removes it for good.');
    final seen = <String>[];
    for (final version in {if (isCatalogIdentifier(package.version)) package.version, null}) {
      final VersionInfo info;
      try {
        info = await _catalog.version(package.id, version);
      } on CatalogException catch (error) {
        if (error.statusCode == 404) continue;
        return copy(note: 'Tizen Archive could not be asked (${error.message}): back up again later.');
      }
      // The very version the watch runs passed the watch's own check: a copy the archive has not verified is good for
      // it too. Another version must be one the archive found installable.
      final same = info.version == package.version;
      final usable = same
          ? const {Verdict.installable, Verdict.unverified, Verdict.unknown}
          : const {Verdict.installable};
      final candidates = info.artifacts.where((artifact) => usable.contains(artifact.verdict));
      final artifact =
          candidates.where((artifact) => artifact.verdict == Verdict.installable).firstOrNull ?? candidates.firstOrNull;
      if (artifact == null) {
        final verdicts = info.buildVerdicts.map(_verdictWords).join('/');
        // The latest version may be the one the watch runs, asked about already
        final found = 'v${info.version} ${verdicts.isEmpty ? 'without files' : verdicts}';
        if (!seen.contains(found)) seen.add(found);
        continue;
      }
      try {
        await _fetch(artifact, download);
      } on CatalogException catch (error) {
        return copy(note: 'The download from Tizen Archive failed (${error.message}): back up again later.');
      }
      final type = await _packageType(download, artifact);
      final entry = 'packages/${safeFileName('${info.name ?? package.name} (${package.id}) v${info.version}', type)}';
      await Directory('${work.path}/packages').create(recursive: true);
      await download.rename('${work.path}/$entry');
      final notes = [
        if (!same) 'The watch has v${package.version}; Tizen Archive has v${info.version}.',
        if (artifact.verdict != Verdict.installable)
          'Tizen Archive has not verified that it installs; it is the version the watch runs now.',
      ];
      return copy(
        entry: entry,
        entryVersion: info.version,
        source: 'Tizen Archive',
        note: notes.isEmpty ? null : notes.join(' '),
      );
    }
    return copy(
      note: seen.isEmpty
          ? 'Not in Tizen Archive, and no file of yours: a reset removes it for good.'
          : 'Tizen Archive has it (${seen.join('; ')}) but no copy fit for this watch: a reset removes it for good.',
    );
  }

  /// Tizen Archive's file, checked against its SHA-256 as it downloads; a copy kept from an earlier backup is used when
  /// its SHA-256 is still right.
  Future<void> _fetch(Artifact artifact, File target) async {
    final cached = _sha256.hasMatch(artifact.sha256) ? File('${_cache.path}/${artifact.sha256.toLowerCase()}') : null;
    if (cached != null &&
        await cached.exists() &&
        await cached.length() == artifact.size &&
        await sha256OfFile(cached) == artifact.sha256.toLowerCase()) {
      await cached.copy(target.path);
      return;
    }
    await _catalog.download(artifact, target);
    if (cached == null) return;
    try {
      await _cache.create(recursive: true);
      await target.copy(cached.path);
    } on FileSystemException {
      // The cache only saves time
    }
  }

  /// The type from the content; when the content cannot be read, from the catalog's file name.
  Future<String> _packageType(File file, Artifact artifact) async {
    try {
      return (await _inspector.read(file)).type;
    } on InvalidPackageException {
      return (artifact.fileName ?? '').toLowerCase().endsWith('.tpk') ? 'tpk' : 'wgt';
    }
  }

  /// The package files among [folder]'s files (`.wgt`, `.tpk`), each read once; others are skipped.
  Future<List<(File, TizenPackageInfo)>> _ownPackages(Directory? folder) async {
    if (folder == null || !await folder.exists()) return const [];
    final packages = <(File, TizenPackageInfo)>[];
    final files = await folder.list().where((entity) => entity is File).cast<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.path.toLowerCase();
      if (!name.endsWith('.wgt') && !name.endsWith('.tpk')) continue;
      try {
        packages.add((file, await _inspector.read(file)));
      } on InvalidPackageException {
        // Not a package after all
      }
    }
    return packages;
  }

  Future<File> _write(Directory folder, _Snapshot snapshot, List<BackupPackage> packages, Directory work) async {
    final now = _clock();
    final manifest = BackupManifest(
      createdAt: isoLocalDateTime(now),
      watch: snapshot.watch,
      packages: packages,
      media: snapshot.media,
    );
    await folder.create(recursive: true);
    final target = File('${folder.path}/${backupFileName(now)}');
    final part = '${target.path}.part';
    final manifestJson = encodeManifest(manifest);
    final reportText = report(manifest);
    final workPath = work.path;
    try {
      await Isolate.run(() => writeBackupArchive(part, manifestJson, reportText, workPath));
      if (await target.exists()) await target.delete();
      return await File(part).rename(target.path);
    } catch (_) {
      final leftover = File(part);
      if (await leftover.exists()) await leftover.delete();
      rethrow;
    }
  }

  Future<void> _installAll(
    WatchConnection watch,
    String backup,
    List<BackupPackage> chosen,
    Set<String> entries,
    Directory temp,
    RestoreResult result,
    BackupProgress progress,
  ) async {
    progress.step('Reading what the watch has…');
    final installed = {for (final package in await watch.listPackages()) package.id: package.version};
    final plan = planInstalls(chosen, installed);
    result.alreadyThere.addAll(plan.alreadyThere.map((package) => package.name));
    result.noCopy.addAll(plan.noCopy.map((package) => package.name));
    for (final (n, package) in plan.install.indexed) {
      final entry = package.entry!;
      if (!entries.contains(entry)) {
        result.failed.add('${package.name}: its file is missing from the backup');
        continue;
      }
      final file = File('${temp.path}/package-$n.${entry.toLowerCase().endsWith('.tpk') ? 'tpk' : 'wgt'}');
      try {
        final target = file.path;
        await Isolate.run(() => extractBackupEntry(backup, entry, target, maxBytes: maxPackageBytes));
        progress.step('Installing ${n + 1} of ${plan.install.length}: ${package.name}…');
        final outcome = await watch.install(file, onProgress: (step) => progress.percent(_percent(step)));
        if (outcome.success) {
          result.installed.add(package.name);
        } else {
          final words = [outcome.message, outcome.code].nonNulls.join(' ');
          result.failed.add('${package.name}: the watch refused it ($words)');
        }
      } on InvalidPackageException catch (error) {
        result.failed.add('${package.name}: not a Tizen package (${error.message})');
      } on FormatException catch (error) {
        result.failed.add('${package.name}: its file in the backup is damaged (${error.message})');
      } on WatchException catch (error) {
        // A package the watch would not take (no space, say) is noted; a lost connection ends the restore
        if (error.error != WatchError.protocol && error.error != WatchError.refused) rethrow;
        result.failed.add('${package.name}: ${error.message}');
      } finally {
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> _copyBack(
    WatchConnection watch,
    String backup,
    List<BackupMedia> chosen,
    Set<String> entries,
    Directory temp,
    RestoreResult result,
    BackupProgress progress,
  ) async {
    progress.step('Reading the files on the watch…');
    final present = await remoteMedia(watch);
    for (final (n, media) in chosen.indexed) {
      final relative = mediaRelative(media.path);
      if (relative == null) {
        result.failed.add('${media.path}: not a place for the user\'s files');
      } else if (!entries.contains(media.entry)) {
        result.failed.add('${media.path}: missing from the backup');
      } else if (present[media.path] == media.size) {
        result.filesAlreadyThere++;
      } else {
        progress.step('Copying back ${n + 1} of ${chosen.length}: $relative');
        final file = File('${temp.path}/media-$n');
        try {
          final target = file.path;
          final entry = media.entry;
          final maxBytes = min(media.size, maxMediaBytes);
          await Isolate.run(() => extractBackupEntry(backup, entry, target, maxBytes: maxBytes));
          await watch.upload(
            media.path,
            file.openRead(),
            length: await file.length(),
            onProgress: (sent) => progress.percent(media.size > 0 ? min(100, sent * 100 ~/ media.size) : -1),
          );
          result.filesCopied++;
        } on WatchException catch (error) {
          // A refused file is noted; a lost connection ends the restore
          if (error.error != WatchError.protocol && error.error != WatchError.refused) rethrow;
          result.failed.add('${media.path}: ${error.message}');
        } on FormatException catch (error) {
          result.failed.add('${media.path}: its copy in the backup is damaged (${error.message})');
        } finally {
          if (await file.exists()) await file.delete();
        }
      }
    }
  }

  static int _percent(InstallProgress step) => switch (step) {
    Uploading(:final sent, :final total) => total > 0 ? min(100, sent * 100 ~/ total) : -1,
    Installing(:final percent) => percent ?? -1,
  };

  static String _verdictWords(Verdict verdict) => switch (verdict) {
    Verdict.installable => 'installable',
    Verdict.deviceBound => 'device bound',
    Verdict.expired => 'expired',
    Verdict.notInstallable => 'not installable',
    Verdict.unverified => 'unverified',
    Verdict.unknown => 'unknown',
  };
}

/// The user's files on the watch, by path, with their sizes; hidden ones and odd names are left out.
Future<Map<String, int>> remoteMedia(WatchConnection watch) async {
  final output = await watch.shell("find $mediaRoot -type f -printf '%s\\t%p\\n' 2>/dev/null");
  final files = <String, int>{};
  for (final line in output.split('\n')) {
    final tab = line.indexOf('\t');
    if (tab < 0) continue;
    final size = int.tryParse(line.substring(0, tab));
    final path = line.substring(tab + 1).replaceFirst(RegExp(r'\r+$'), '');
    if (size != null && size >= 0 && mediaRelative(path) != null) files[path] = size;
  }
  return files;
}

/// A package a reset removes or rolls back, as the watch lists it.
class _WatchedPackage {
  _WatchedPackage(this.id, this.name, this.version, this.type, this.origin);

  final String id;
  final String name;
  final String version;
  final String type;
  final PackageOrigin origin;
}

/// What one pass over the watch read; the files themselves are in the work folder.
class _Snapshot {
  _Snapshot(this.watch, this.packages, this.media);

  final String watch;
  final List<_WatchedPackage> packages;
  final List<BackupMedia> media;
}
