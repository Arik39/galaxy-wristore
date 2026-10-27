import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import 'local_network.dart';
import 'services.dart';

/// Where the conversation with the watch stands, each with one next step for the user.
enum LinkPhase {
  /// No address yet: the first run.
  notSetUp,
  connecting,

  /// The watch is showing "Allow debugging" and waits for a tap.
  waitingForApproval,
  connected,

  /// Nothing answered at the address.
  unreachable,

  /// The port answered, the watch did not: Debugging is off or needs a restart.
  notAnswering,

  /// Another device holds the watch.
  busy,
  failed,
}

/// What the phone is doing with the watch.
enum Job { checking, installing, removing, backingUp, restoring, ringing, opening }

/// A long job the phone is doing with the watch, as the bezel and the screens show it.
class Operation {
  const Operation(this.label, {this.progress = -1});

  final String label;

  /// 0 to 1, or -1 while the amount is unknown.
  final double progress;
}

/// A backup file the app knows about, with what it holds.
class BackupRecord {
  const BackupRecord({
    required this.file,
    required this.createdAt,
    required this.watch,
    required this.idsWithCopy,
    this.idsUnsaveable = const {},
    required this.packageCount,
    required this.mediaCount,
  });

  final File? file;
  final DateTime createdAt;
  final String watch;
  final Set<String> idsWithCopy;

  /// Packages the backup could get no copy of for good: Tizen Archive does not have one that fits, and an installed
  /// package cannot be copied off the watch. (A copy missing because the archive could not be reached is not here: a
  /// new backup may still get it.)
  final Set<String> idsUnsaveable;
  final int packageCount;
  final int mediaCount;

  /// Whether a package the backup holds no copy of is one no backup can save: its note says so, unlike a note that
  /// asks to back up again later.
  static bool unsaveable(BackupPackage p) => p.entry == null && !(p.note ?? '').contains('again later');
}

/// A backup service that keeps its backups itself, not as files in the backup folder: the demo's.
abstract interface class KnownBackups {
  List<BackupRecord> get records;
}

/// The watch as the app knows it, and every action on it. Screens listen to it.
///
/// Each action opens its own connection and closes it when done: the watch serves one device at a time, and a phone
/// should not hold it while its owner uses the Mac app or another phone.
class WatchController extends ChangeNotifier {
  WatchController(this.services, this._prefs);

  final Services services;
  final SharedPreferences _prefs;

  static const _addressKey = 'watch.address';

  WatchAddress? address;
  LinkPhase phase = LinkPhase.notSetUp;

  /// What went wrong and the one thing that fixes it, in plain words; null when all is well.
  String? problem;
  WatchIdentity? identity;
  WatchStatus? status;
  List<WatchPackage> packages = const [];
  DateTime? checkedAt;
  List<BackupRecord> backups = const [];
  Operation? operation;

  /// The job running now, null when the phone is idle.
  Job? job;

  /// Goes up by one each time a job finishes, so the watch can take a bow.
  int presentations = 0;

  bool _busy = false;
  bool _ringing = false;

  /// The connection of the job running now, so a stop can close it under the job.
  WatchConnection? _watch;
  bool _stopRequested = false;

  /// Whether the last job ended because the user stopped it.
  bool wasStopped = false;

  /// Completed to drop a connection that waits for the watch's "Allow debugging" answer.
  Completer<void>? _giveUp;
  bool _askingAgain = false;

  /// How many times this phone offered its key since the watch last answered, for the screen to say so.
  int askedTimes = 0;

  /// Package pictures fetched from the watch, kept on the phone by package id.
  final Map<String, File> _pictures = {};
  Directory? _pictureFolder;

  /// The face on the wrist, when the watch would tell; null when unknown.
  String? currentFaceId;

  /// The picture of a package (a face's preview, an app's icon), once fetched from the watch.
  File? pictureOf(String packageId) => _pictures[packageId];

  Future<void> start() async {
    await _loadPictures();
    address = WatchAddress.parse(_prefs.getString(_addressKey) ?? '');
    if (services.demo && address == null) address = WatchAddress.parse('192.168.2.66');
    await loadBackups();
    if (address != null) {
      phase = LinkPhase.connecting;
      notifyListeners();
      await refresh();
    }
  }

  Future<void> setAddress(WatchAddress value) async {
    address = value;
    await _prefs.setString(_addressKey, value.host);
    await refresh();
  }

  /// Looks for the watch in the phone's Wi-Fi network.
  Future<List<FoundWatch>> find({void Function(double fraction)? onProgress}) async {
    if (!services.demo && !await ensureLocalNetwork()) throw const LocalNetworkDenied();
    return services.finder.find(onProgress: onProgress);
  }

  /// Reads the watch's state: who it is, battery and storage, and its packages.
  Future<void> refresh() => _withWatch(Job.checking, 'Checking your watch', (watch) async {
    identity = watch.identity;
    status = await watch.status();
    packages = await watch.listPackages();
    checkedAt = DateTime.now();
    notifyListeners();
    await _readCurrentFace(watch);
    await _fetchPictures(watch);
  });

  /// Installs a package file and reads the watch again. Progress runs from [startAt] to 1, so a download before it
  /// can fill the first part of the bezel.
  Future<InstallResult?> install(File package, {required String name, double startAt = 0}) async {
    InstallResult? result;
    await _withWatch(Job.installing, 'Installing $name', (watch) async {
      result = await watch.install(
        package,
        onProgress: (p) {
          final fraction = switch (p) {
            Uploading(:final sent, :final total) => total > 0 ? 0.6 * sent / total : -1.0,
            Installing(:final percent) => percent == null ? -1.0 : 0.6 + 0.4 * percent / 100,
          };
          _report(Operation('Installing $name', progress: fraction < 0 ? -1 : startAt + (1 - startAt) * fraction));
        },
      );
      if (result!.success) packages = await watch.listPackages();
    }, celebrate: true);
    return result;
  }

  /// Downloads a package from Tizen Archive, checks its size and SHA-256, then installs it. The download needs no
  /// watch; the watch is connected only for the install. Returns null when it worked, otherwise why not, in plain words.
  Future<String?> installFromCatalog(String packageId, String name) async {
    if (_busy || operation != null) return 'The phone is still busy with your watch. Try again in a moment.';
    final VersionInfo info;
    try {
      info = await services.catalog.version(packageId);
    } on CatalogException catch (e) {
      return 'Tizen Archive did not answer: ${e.message}';
    }
    final choice = services.catalog.choose(info);
    if (choice is ArtifactNone) return notInstallableText(choice.reason);
    final artifact = (choice as ArtifactFound).artifact;
    final temp = File('${(await getTemporaryDirectory()).path}/wristore-${DateTime.now().microsecondsSinceEpoch}.pkg');
    // The download needs no watch, but nothing else may start with it until the install is done.
    _busy = true;
    job = Job.installing;
    try {
      _report(Operation('Downloading $name', progress: 0));
      await services.catalog.download(
        artifact,
        temp,
        onProgress: (received) {
          _report(Operation('Downloading $name', progress: artifact.size > 0 ? 0.35 * received / artifact.size : -1));
        },
      );
      _busy = false;
      final result = await install(temp, name: name, startAt: 0.35);
      if (result == null) return problem ?? 'Your watch could not be reached.';
      return result.success ? null : 'Your watch refused it: ${result.message ?? result.code ?? 'no reason given'}.';
    } on CatalogException catch (e) {
      return 'The download failed: ${e.message}';
    } finally {
      if (_busy) {
        _busy = false;
        job = null;
        operation = null;
        notifyListeners();
      }
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  static String notInstallableText(NotInstallableReason reason) => switch (reason) {
    NotInstallableReason.noBuilds => 'Tizen Archive has no file of this version.',
    NotInstallableReason.notDownloadable => 'Tizen Archive cannot share this file.',
    NotInstallableReason.deviceBound => 'It is signed for a few specific watches, so yours would refuse it.',
    NotInstallableReason.expired => 'Its signing certificate has expired, so watches refuse it.',
    NotInstallableReason.rejectedByWatch => 'Watches refuse its signature.',
    NotInstallableReason.unverified => 'Nobody has confirmed yet that watches accept it.',
  };

  /// Removes a package the user added, with its data on the watch.
  Future<InstallResult?> uninstall(WatchPackage package) async {
    InstallResult? result;
    await _withWatch(Job.removing, 'Removing ${package.name}', (watch) async {
      result = await watch.uninstall(package.id);
      packages = await watch.listPackages();
    });
    return result;
  }

  /// Makes a backup file of everything a reset erases that can be saved.
  Future<File?> backUp() async {
    File? file;
    final folder = await backupFolder();
    await _withWatch(Job.backingUp, 'Backing up', (watch) async {
      file = await services.backups.create(watch, folder, progress: _Progress(this, 'Backing up'));
    }, celebrate: true);
    await loadBackups();
    return file;
  }

  /// Puts back what the user picked from a backup.
  Future<RestoreResult?> restore(
    File backup, {
    required Set<String> packageIds,
    required Set<String> mediaPaths,
  }) async {
    RestoreResult? result;
    await _withWatch(Job.restoring, 'Restoring', (watch) async {
      result = await services.backups.restore(
        watch,
        backup,
        packageIds: packageIds,
        mediaPaths: mediaPaths,
        progress: _Progress(this, 'Restoring'),
      );
      packages = await watch.listPackages();
    }, celebrate: true);
    return result;
  }

  Future<void> _withWatch(
    Job what,
    String label,
    Future<void> Function(WatchConnection watch) work, {
    bool celebrate = false,
  }) async {
    final at = address;
    if (at == null || _busy) return;
    _busy = true;
    job = what;
    operation = Operation(label);
    if (phase != LinkPhase.connected) phase = LinkPhase.connecting;
    problem = null;
    wasStopped = false;
    notifyListeners();
    WatchConnection? watch;
    try {
      if (!services.demo && !await ensureLocalNetwork()) {
        phase = LinkPhase.failed;
        problem = const LocalNetworkDenied().message;
        return;
      }
      watch = _watch = await _connect(at);
      phase = LinkPhase.connected;
      notifyListeners();
      await work(watch);
      if (celebrate) presentations++;
    } on _Stopped {
      wasStopped = true;
    } on WatchException catch (e) {
      // A stop closes the connection under the job: that is the user's doing, not the watch's.
      if (_stopRequested) {
        wasStopped = true;
      } else {
        _explain(e, at);
      }
    } on CatalogException catch (e) {
      problem = 'Tizen Archive: ${e.message}';
    } on InvalidPackageException catch (e) {
      problem = 'That file is not a package the watch can install: ${e.message}';
    } on Exception catch (e) {
      if (_stopRequested) {
        wasStopped = true;
      } else {
        problem = 'Something went wrong: $e';
      }
    } finally {
      _watch = null;
      await watch?.close();
      _busy = false;
      _stopRequested = false;
      job = null;
      operation = null;
      notifyListeners();
    }
  }

  /// Stops a running backup: a transfer from the watch ends at once, the rest at its next step. Nothing of it is kept.
  void stopBackUp() {
    if (job != Job.backingUp || _stopRequested) return;
    _stopRequested = true;
    _report(const Operation('Stopping the backup'));
    _watch?.close();
  }

  bool get stopping => _stopRequested;

  /// Connects, and connects again each time the user asks for the watch's "Allow debugging" question again.
  Future<WatchConnection> _connect(WatchAddress at) async {
    askedTimes = 0;
    while (true) {
      final giveUp = _giveUp = Completer<void>();
      try {
        final watch = await services.connector.connect(
          at,
          giveUp: giveUp.future,
          onApprovalNeeded: () {
            askedTimes++;
            phase = LinkPhase.waitingForApproval;
            notifyListeners();
          },
        );
        return watch;
      } on WatchException {
        if (!_askingAgain) rethrow;
        _askingAgain = false;
        phase = LinkPhase.connecting;
        notifyListeners();
      } finally {
        _giveUp = null;
      }
    }
  }

  /// Offers this phone's key to the watch once more, for when its "Allow debugging" question did not show or went
  /// away: the waiting connection is dropped and a new one makes the watch ask again.
  void askAgain() {
    final giveUp = _giveUp;
    if (phase != LinkPhase.waitingForApproval || giveUp == null || giveUp.isCompleted) return;
    _askingAgain = true;
    giveUp.complete();
  }

  void _explain(WatchException e, WatchAddress at) {
    switch (e.error) {
      case WatchError.unreachable:
        phase = LinkPhase.unreachable;
        problem = 'Nothing answered at $at. Check that your watch is on the same Wi-Fi as this phone and awake.';
      case WatchError.notAnswering:
        phase = LinkPhase.notAnswering;
        problem = 'Your watch is not answering. Turn on Debugging in its settings; if it is on, restart the watch.';
      case WatchError.busy:
        phase = LinkPhase.busy;
        problem = 'Another device is connected to your watch. Close the other app, then try again.';
      case WatchError.approvalTimeout:
        phase = LinkPhase.failed;
        problem = 'Your watch asked to allow this phone. Tap the check mark on the watch when it asks again.';
      case WatchError.lost || WatchError.refused || WatchError.protocol:
        phase = LinkPhase.failed;
        problem = 'The connection to your watch broke: ${e.message}. Wake the watch and try again.';
    }
  }

  // ---- Pictures ----

  /// Package ids as the watch lists them; anything else never reaches a shell command.
  static final _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

  Future<void> _loadPictures() async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory('${support.path}/pictures');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    _pictureFolder = folder;
    for (final file in folder.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.png')) _pictures[name.substring(0, name.length - 4)] = file;
    }
  }

  /// Fetches the pictures of downloaded packages the phone has not seen yet: each package's icon, which for a watch
  /// face is a preview of the whole face. The watch lets its debugging shell read them; nothing else is read.
  Future<void> _fetchPictures(WatchConnection watch) async {
    final folder = _pictureFolder;
    if (folder == null) return;
    for (final p in downloaded) {
      if (_pictures.containsKey(p.id) || !_safeId.hasMatch(p.id)) continue;
      try {
        final info = await watch.shell('pkginfo --pkg ${p.id}');
        final path = RegExp(
          r'^Icon:\s*(/opt/usr/globalapps/[^\r\n]+?)\s*$',
          multiLine: true,
        ).firstMatch(info)?.group(1);
        if (path == null || path.contains('..')) continue;
        final bytes = await watch.pull(path, maxBytes: 2 << 20);
        if (bytes.length < 64) continue;
        final file = File('${folder.path}/${p.id}.png');
        await file.writeAsBytes(bytes, flush: true);
        _pictures[p.id] = file;
        notifyListeners();
      } on WatchException {
        // A picture the watch will not give is simply not shown.
      }
    }
  }

  /// Asks the watch which face it wears. Unverified on real watches: when the answer is not a face it has, the dial
  /// shows the default face rather than a guess.
  /// Finds the face on the wrist among the running apps: a face runs while the watch shows it. (The watch's own
  /// setting for it cannot be read over Debugging.) A face's app id is its package id, or starts with it.
  Future<void> _readCurrentFace(WatchConnection watch) async {
    try {
      final out = await watch.shell('app_launcher -S 2>/dev/null');
      final running = {
        for (final m in RegExp(r'^\s*([A-Za-z0-9._-]+) \(\d+\)\s*$', multiLine: true).allMatches(out)) m.group(1)!,
      };
      currentFaceId = faces
          .where((f) => running.contains(f.id) || running.any((r) => r.startsWith('${f.id}.')))
          .firstOrNull
          ?.id;
    } on WatchException {
      currentFaceId = null;
    }
  }

  // ---- The watch as a remote: ringing it, opening its own screens ----

  /// The watch's own Find My Gear tone, played by its debugging shell. The watch refuses vibration over Debugging, so
  /// finding it is by sound alone.
  static const ringTone = '/usr/share/feedback.wearable/sound/System/Find_my_Gear.ogg';

  /// How long the watch rings at most when nobody stops it.
  static const ringFor = Duration(minutes: 1);

  bool get ringing => job == Job.ringing;

  /// Makes the watch play its find tone again and again until [stopRinging], for at most [ringFor]. It works only while
  /// the watch is on the same Wi-Fi as the phone.
  Future<void> ring() => _withWatch(Job.ringing, 'Ringing your watch', (watch) async {
    _ringing = true;
    final until = DateTime.now().add(ringFor);
    while (_ringing && DateTime.now().isBefore(until)) {
      final out = await watch.shell('paplay $ringTone 2>&1; echo "exit=\$?"');
      if (!out.contains('exit=0')) {
        problem = 'Your watch would not play its find tone: ${out.trim().split('\n').first}';
        break;
      }
    }
    _ringing = false;
  });

  /// Stops the ringing after the tone that is playing now.
  void stopRinging() {
    _ringing = false;
    notifyListeners();
  }

  /// Opens one of the watch's own screens, e.g. its sound settings, by app id. Returns null when the watch opened it,
  /// otherwise why not, in plain words.
  Future<String?> openOnWatch(String appId) async {
    if (!_safeId.hasMatch(appId)) return 'That is not something the watch can open.';
    String? failure;
    await _withWatch(Job.opening, 'Opening on your watch', (watch) async {
      final out = await watch.shell('app_launcher -s $appId 2>&1');
      if (!out.contains('successfully launched')) failure = 'Your watch did not open it: ${out.trim()}';
    });
    return problem ?? failure;
  }

  // ---- Backups ----

  static Future<Directory> backupFolder() async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory('${documents.path}/Backups');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return folder;
  }

  Future<void> loadBackups() async {
    final records = <BackupRecord>[];
    if (services.backups case final KnownBackups known) {
      records.addAll(known.records);
    } else {
      final folder = await backupFolder();
      for (final file in folder.listSync().whereType<File>().where((f) => f.path.endsWith('.twbackup'))) {
        try {
          final contents = await services.backups.open(file);
          final m = contents.manifest;
          records.add(
            BackupRecord(
              file: file,
              createdAt: DateTime.tryParse(m.createdAt) ?? file.lastModifiedSync(),
              watch: m.watch,
              idsWithCopy: {
                for (final p in m.packages)
                  if (p.entry != null) p.id,
              },
              idsUnsaveable: {
                for (final p in m.packages)
                  if (BackupRecord.unsaveable(p)) p.id,
              },
              packageCount: m.packages.length,
              mediaCount: m.media.length,
            ),
          );
          await contents.close();
        } on Exception {
          // A damaged or foreign file is left out of the list.
        }
      }
    }
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    backups = records;
    notifyListeners();
  }

  // ---- What the screens show ----

  BackupRecord? get latestBackup => backups.isEmpty ? null : backups.first;

  /// What a reset removes: apps and faces downloaded to the watch.
  List<WatchPackage> get downloaded => [
    for (final p in packages)
      if (p.origin == PackageOrigin.downloaded) p,
  ];

  List<WatchPackage> get faces => [
    for (final p in packages)
      if (kindOf(p) == PackageKind.watchFace) p,
  ];

  List<WatchPackage> get apps => [
    for (final p in packages)
      if (kindOf(p) == PackageKind.app) p,
  ];

  /// Downloaded packages the latest backup has no copy of: a reset would remove them for good.
  List<WatchPackage> get notBackedUp {
    final ids = latestBackup?.idsWithCopy ?? const <String>{};
    return [
      for (final p in downloaded)
        if (!ids.contains(p.id)) p,
    ];
  }

  int get backedUpCount => downloaded.length - notBackedUp.length;

  /// Of what a reset would remove, what no backup can save: the latest backup found no copy in Tizen Archive.
  List<WatchPackage> get unsaveable {
    final ids = latestBackup?.idsUnsaveable ?? const <String>{};
    return [
      for (final p in notBackedUp)
        if (ids.contains(p.id)) p,
    ];
  }

  /// What a new backup could still save: added since the latest backup, or missed because the archive was not reached.
  List<WatchPackage> get toBackUp {
    final unsaveableIds = {for (final p in unsaveable) p.id};
    return [
      for (final p in notBackedUp)
        if (!unsaveableIds.contains(p.id)) p,
    ];
  }

  void _report(Operation value) {
    operation = value;
    notifyListeners();
  }

  static PackageKind kindOf(WatchPackage p) =>
      p.kind ?? (p.id.startsWith('com.watchface.') ? PackageKind.watchFace : PackageKind.app);
}

/// Thrown from a backup's progress once the user stops it, so the backup ends at its next step and cleans up.
class _Stopped implements Exception {
  const _Stopped();
}

class _Progress implements BackupProgress {
  _Progress(this._owner, this._label);

  final WatchController _owner;
  String _label;

  @override
  void step(String text) {
    if (_owner._stopRequested) throw const _Stopped();
    _label = text;
    _owner._report(Operation(text, progress: _owner.operation?.progress ?? -1));
  }

  @override
  void percent(int? value) {
    if (_owner._stopRequested) throw const _Stopped();
    _owner._report(Operation(_label, progress: value == null || value < 0 ? -1 : value / 100));
  }
}
