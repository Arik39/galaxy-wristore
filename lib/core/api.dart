/// The contract between Galaxy Wristore's screens and the code that talks to the watch, to Tizen Archive and to backup
/// files. Screens depend on these types only; the implementations live beside this file in `lib/core/`.
///
/// Ported from the Kotlin `core` and `cli` modules of Tizen Companion Installer (Apache-2.0); behaviour, limits and
/// file formats stay compatible with it, so a backup made by the Mac app opens here and the other way round.
library;

import 'dart:io';
import 'dart:typed_data';

// ---------------------------------------------------------------------------------------------------------------
// The watch
// ---------------------------------------------------------------------------------------------------------------

/// A watch's address: a private IPv4 address in the local network. sdb listens on [sdbPort].
class WatchAddress {
  const WatchAddress._(this.host);

  final String host;

  static const int sdbPort = 26101;

  /// "192.168.2.66" and the like; null for anything that is not a private IPv4 address (10/8, 172.16/12, 192.168/16),
  /// so a typed or remembered address can never point the app at the internet.
  static WatchAddress? parse(String text) {
    final parts = text.trim().split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > 3 || part.codeUnits.any((c) => c < 0x30 || c > 0x39)) return null;
      final value = int.parse(part);
      if (value > 255) return null;
      octets.add(value);
    }
    final private =
        octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
    if (!private || octets[3] == 0 || octets[3] == 255) return null;
    return WatchAddress._(octets.join('.'));
  }

  @override
  bool operator ==(Object other) => other is WatchAddress && other.host == host;

  @override
  int get hashCode => host.hashCode;

  @override
  String toString() => host;
}

/// Why talking to the watch failed, in terms a screen can explain with one next step.
enum WatchError {
  /// Nothing answered at the address: wrong address, other network, or the watch's Wi-Fi is off.
  unreachable,

  /// The port answered but the watch never replied: Debugging is off, or the watch needs a restart after switching it on.
  notAnswering,

  /// Another computer or phone is connected to the watch; it serves one at a time.
  busy,

  /// The watch was asked to allow this phone and the user did not tap the check mark in time.
  approvalTimeout,

  /// The connection broke or timed out in the middle of a conversation.
  lost,

  /// The watch refused a service or a file (for example a path outside the media folder).
  refused,

  /// The watch answered something this app does not understand.
  protocol,
}

class WatchException implements Exception {
  const WatchException(this.error, this.message);

  final WatchError error;
  final String message;

  @override
  String toString() => 'WatchException($error): $message';
}

/// What the watch says about itself in its connection banner, e.g. `device::SM-R800::0` plus what `shell` can read.
class WatchIdentity {
  const WatchIdentity({required this.banner, this.model, this.tizenVersion, this.name});

  final String banner;

  /// "SM-R800"; null when unknown.
  final String? model;

  /// "5.5"; null when unknown.
  final String? tizenVersion;

  /// A human name such as "Galaxy Watch 46 mm"; null when unknown.
  final String? name;
}

/// Battery and storage, read over the debugging shell. Every field is null when the watch would not tell.
class WatchStatus {
  const WatchStatus({this.batteryPercent, this.charging, this.storageFreeBytes, this.storageTotalBytes});

  final int? batteryPercent;
  final bool? charging;
  final int? storageFreeBytes;
  final int? storageTotalBytes;
}

/// Where a package on the watch came from, as `pkginfo` reports it (Preload and update flags).
enum PackageOrigin { builtIn, builtInUpdated, downloaded }

/// What a package is to the user.
enum PackageKind { watchFace, app }

/// A package installed on the watch.
class WatchPackage {
  const WatchPackage({
    required this.id,
    required this.name,
    required this.version,
    required this.type,
    this.origin,
    this.kind,
  });

  /// Package id, e.g. `com.watchface.GSHybrid7`.
  final String id;
  final String name;
  final String version;

  /// `tpk` (native) or `wgt` (web).
  final String type;

  /// Null when the watch did not report it.
  final PackageOrigin? origin;

  /// Null when it could not be told.
  final PackageKind? kind;
}

/// How far an installation is.
sealed class InstallProgress {
  const InstallProgress();
}

class Uploading extends InstallProgress {
  const Uploading(this.sent, this.total);

  final int sent;
  final int total;
}

class Installing extends InstallProgress {
  const Installing(this.percent);

  /// Null while the watch has not reported a percentage.
  final int? percent;
}

/// The watch package manager's answer. When it refuses, [message] and [code] are its own words, shown as they are.
class InstallResult {
  const InstallResult({required this.success, this.message, this.code});

  final bool success;
  final String? message;
  final String? code;
}

/// An authorized conversation with one watch. Only one exists at a time: the watch serves one host at a time.
abstract interface class WatchConnection {
  WatchAddress get address;

  WatchIdentity get identity;

  /// Runs [command] in the watch's debugging shell (a limited user) and returns what it printed.
  Future<String> shell(String command);

  /// Every package on the watch, system ones included, with [WatchPackage.origin] filled in.
  Future<List<WatchPackage>> listPackages();

  /// Battery and storage, best effort.
  Future<WatchStatus> status();

  /// Sends a `.tpk` or `.wgt` and installs it with the watch's own package manager (`pkgcmd -w`, which accepts
  /// store-signed packages). The package is never modified.
  Future<InstallResult> install(File package, {void Function(InstallProgress progress)? onProgress});

  /// Removes a downloaded package (and its data on the watch).
  Future<InstallResult> uninstall(String packageId);

  /// Writes [data] ([length] bytes) to [remotePath] on the watch; refused for paths that are not absolute or that
  /// contain `..`, commas or control characters.
  Future<void> upload(
    String remotePath,
    Stream<List<int>> data, {
    required int length,
    int mode = 420,
    void Function(int sent)? onProgress,
  });

  /// Reads a file from the watch, refusing more than [maxBytes].
  Future<Uint8List> pull(String remotePath, {int maxBytes = 64 << 20, void Function(int received)? onProgress});

  Future<void> close();
}

/// Opens [WatchConnection]s with the app's own key. The key is made once and kept in the platform's secure storage;
/// the first time, the watch asks its user to allow this phone, and [onApprovalNeeded] lets the screen say so.
abstract interface class WatchConnector {
  Future<WatchConnection> connect(WatchAddress address, {void Function()? onApprovalNeeded});
}

/// A watch found by [WatchFinder]: something answering sdb at [address]. [busy] when another host holds it.
class FoundWatch {
  const FoundWatch(this.address, {this.busy = false});

  final WatchAddress address;
  final bool busy;
}

/// Looks for watches in the phone's Wi-Fi network by probing port 26101 (a hello only: it never asks the watch to
/// allow anything).
abstract interface class WatchFinder {
  Future<List<FoundWatch>> find({void Function(double fraction)? onProgress});
}

// ---------------------------------------------------------------------------------------------------------------
// Tizen Archive
// ---------------------------------------------------------------------------------------------------------------

enum CatalogKind { watchFace, app }

/// Tizen Archive's prediction of whether a watch accepts a package's signature.
enum Verdict { installable, deviceBound, expired, notInstallable, unverified, unknown }

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    this.kind,
    this.iconPath,
    this.verdict = Verdict.unknown,
    this.latestVersion,
  });

  final String id;
  final String name;
  final CatalogKind? kind;

  /// A path below `/api/icons/` for [CatalogApi.icon]; null without an icon.
  final String? iconPath;
  final Verdict verdict;
  final String? latestVersion;
}

class CatalogPage {
  const CatalogPage({required this.items, required this.page, required this.hasMore, this.total});

  final List<CatalogEntry> items;
  final int page;
  final bool hasMore;
  final int? total;
}

class VersionSummary {
  const VersionSummary({required this.version, this.verdict = Verdict.unknown});

  final String version;
  final Verdict verdict;
}

class PackageDetails {
  const PackageDetails({
    required this.id,
    required this.name,
    this.description,
    this.authorName,
    this.iconPath,
    this.latestVersion,
    this.versions = const [],
  });

  final String id;
  final String name;
  final String? description;
  final String? authorName;
  final String? iconPath;
  final String? latestVersion;
  final List<VersionSummary> versions;
}

/// One downloadable file of a version, with the checksum the download is verified against.
class Artifact {
  const Artifact({
    required this.downloadUrl,
    required this.sha256,
    required this.size,
    this.fileName,
    this.verdict = Verdict.unknown,
  });

  final String downloadUrl;
  final String sha256;
  final int size;
  final String? fileName;
  final Verdict verdict;
}

class VersionInfo {
  const VersionInfo({
    required this.id,
    required this.version,
    this.name,
    this.artifacts = const [],
    this.buildVerdicts = const [],
  });

  final String id;
  final String version;
  final String? name;

  /// The downloadable files, build by build (the primary build first), each with its build's verdict.
  final List<Artifact> artifacts;

  /// The verdict of every build, the primary one first, including builds without a downloadable file; with
  /// [artifacts] it tells [CatalogApi.choose] why nothing can be installed.
  final List<Verdict> buildVerdicts;
}

/// Which file of a version to install, or why none can be.
sealed class ArtifactChoice {
  const ArtifactChoice();
}

class ArtifactFound extends ArtifactChoice {
  const ArtifactFound(this.artifact);

  final Artifact artifact;
}

enum NotInstallableReason { noBuilds, notDownloadable, deviceBound, expired, rejectedByWatch, unverified }

class ArtifactNone extends ArtifactChoice {
  const ArtifactNone(this.reason);

  final NotInstallableReason reason;
}

class CatalogException implements Exception {
  const CatalogException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'CatalogException: $message';
}

/// Tizen Archive's REST API. Its address is fixed in the app; nothing a user or a link supplies can change it.
abstract interface class CatalogApi {
  Future<CatalogPage> search({String query = '', CatalogKind? kind, bool installableOnly = true, int page = 1});

  Future<PackageDetails> details(String packageId);

  /// One version, the latest when [version] is null.
  Future<VersionInfo> version(String packageId, [String? version]);

  /// Picks the file to install from [info] the way the Kotlin `ArtifactSelection` does.
  ArtifactChoice choose(VersionInfo info);

  /// An icon by its `/api/icons/...` path; refuses other paths and anything over 512 KB.
  Future<Uint8List> icon(String path);

  /// Downloads [artifact] to [target] and checks its size and SHA-256; on a mismatch the file is deleted and a
  /// [CatalogException] thrown.
  Future<void> download(Artifact artifact, File target, {void Function(int received)? onProgress});
}

// ---------------------------------------------------------------------------------------------------------------
// Package files
// ---------------------------------------------------------------------------------------------------------------

class TizenPackageInfo {
  const TizenPackageInfo({
    required this.packageId,
    required this.type,
    this.version,
    this.displayName,
    this.iconPath,
    this.kind,
  });

  final String packageId;

  /// `tpk` or `wgt`.
  final String type;
  final String? version;
  final String? displayName;

  /// The icon's path inside the package.
  final String? iconPath;
  final PackageKind? kind;
}

class PackageImage {
  const PackageImage(this.path, this.bytes);

  final String path;
  final Uint8List bytes;
}

/// A prediction from the certificate chain of whether the watch will accept a package; it never blocks sending.
enum SignatureVerdict { storeSigned, deviceBound, expired, untrusted, unsigned, unknown }

class InvalidPackageException implements Exception {
  const InvalidPackageException(this.message);

  final String message;

  @override
  String toString() => 'InvalidPackageException: $message';
}

abstract interface class PackageInspector {
  /// Reads the manifest of a `.tpk` or `.wgt`; throws [InvalidPackageException] for anything else.
  Future<TizenPackageInfo> read(File file);

  /// The pictures inside a package: its icon first, then the largest, each once; small files (digits, hands) left out.
  Future<List<PackageImage>> images(File file, {int maxImages = 12, int maxBytes = 4 << 20});

  Future<SignatureVerdict> signature(File file);
}

// ---------------------------------------------------------------------------------------------------------------
// Backups (`.twbackup`, the same format 1 as the Mac app's)
// ---------------------------------------------------------------------------------------------------------------

/// An app or watch face a reset removes; [entry] is null when the backup has no copy of it.
class BackupPackage {
  const BackupPackage({
    required this.id,
    required this.name,
    required this.version,
    required this.type,
    required this.origin,
    this.entry,
    this.entryVersion,
    this.source,
    this.note,
  });

  final String id;
  final String name;
  final String version;
  final String type;

  /// `downloaded` or `built_in_updated`, as written by the Mac app.
  final String origin;

  /// The copy's name inside the backup, e.g. `packages/GS Hybrid 7 (com.watchface.GSHybrid7) v1.0.1.tpk`.
  final String? entry;
  final String? entryVersion;

  /// Where the copy came from, e.g. "Tizen Archive" or "Your file".
  final String? source;
  final String? note;
}

/// A file of the user's from the watch's media folder.
class BackupMedia {
  const BackupMedia({required this.path, required this.size, required this.entry});

  final String path;
  final int size;
  final String entry;
}

class BackupManifest {
  const BackupManifest({
    this.format = 1,
    required this.createdAt,
    required this.watch,
    required this.packages,
    required this.media,
  });

  final int format;

  /// ISO local date-time, e.g. `2026-10-26T11:47:51`.
  final String createdAt;

  /// The watch's banner, e.g. `device::SM-R800::0`.
  final String watch;
  final List<BackupPackage> packages;
  final List<BackupMedia> media;
}

/// A package of an opened backup, with what its fingerprint tells.
class BackupItem {
  const BackupItem({required this.package, required this.kind, this.manifestXml});

  final BackupPackage package;
  final PackageKind kind;
  final String? manifestXml;
}

/// An opened backup file. Close it when done.
abstract interface class BackupContents {
  File get file;

  BackupManifest get manifest;

  /// The packages with a copy, watch faces first, then by name.
  List<BackupItem> get items;

  /// The picture that best shows a package (for a watch face, a preview of the whole face); null without one.
  Future<Uint8List?> thumbnail(BackupItem item);

  /// Every picture of a package: its fingerprint's first, then those inside its package file, each once.
  Future<List<Uint8List>> pictures(BackupItem item);

  /// The bytes of one of the user's files, for previewing pictures; null when missing or too large.
  Future<Uint8List?> mediaBytes(BackupMedia media, {int maxBytes = 32 << 20});

  Future<void> close();
}

/// What a backup or restore tells its user while it runs.
abstract interface class BackupProgress {
  /// A new step, worth a line in a log.
  void step(String text);

  /// How far the step is: null hides the bar, -1 shows it moving without a percentage.
  void percent(int? value);
}

class RestoreResult {
  final List<String> installed = [];
  final List<String> alreadyThere = [];
  final List<String> noCopy = [];
  final List<String> failed = [];
  int filesCopied = 0;
  int filesAlreadyThere = 0;
}

abstract interface class BackupService {
  /// Saves into one file everything a reset erases that can be saved: copies of downloaded apps and faces (the user's
  /// own package files in [extraPackages] first, then Tizen Archive), the user's files from the watch's media folder,
  /// and a fingerprint of every app. Returns the new `.twbackup` file in [folder].
  Future<File> create(
    WatchConnection watch,
    Directory folder, {
    Directory? extraPackages,
    required BackupProgress progress,
  });

  /// Opens a backup file; throws [FormatException] for a file that is not one.
  Future<BackupContents> open(File backup);

  /// Puts back only what the user chose: the packages in [packageIds] the watch lacks or has older, and the files in
  /// [mediaPaths] (written only into the media folder).
  Future<RestoreResult> restore(
    WatchConnection watch,
    File backup, {
    Set<String> packageIds = const {},
    Set<String> mediaPaths = const {},
    required BackupProgress progress,
  });
}
