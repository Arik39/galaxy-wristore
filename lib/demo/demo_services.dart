import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../app/services.dart';
import '../app/watch_controller.dart';
import '../core/api.dart';
import 'demo_art.dart';

/// A demo watch and catalog for building and reviewing the screens without a watch on the network. Only used when the
/// app is built with `--dart-define=WRISTORE_DEMO=true`; every screen then says "Demo watch". The packages are names
/// from Tizen Archive's public catalog; the figures are made up.
Services demoServices() {
  _DemoConnection._packages
    ..clear()
    ..addAll(_DemoConnection._initial);
  final catalog = _DemoCatalog();
  return Services(
    connector: _DemoConnector(),
    finder: _DemoFinder(),
    catalog: catalog,
    inspector: _DemoInspector(),
    backups: _DemoBackups(),
    demo: true,
  );
}

const _address = '192.168.2.66';

class _DemoFinder implements WatchFinder {
  @override
  Future<List<FoundWatch>> find({void Function(double fraction)? onProgress}) async {
    for (var i = 1; i <= 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      onProgress?.call(i / 20);
    }
    return [FoundWatch(WatchAddress.parse(_address)!)];
  }
}

class _DemoConnector implements WatchConnector {
  bool _allowed = false;

  @override
  Future<WatchConnection> connect(
    WatchAddress address, {
    void Function()? onApprovalNeeded,
    Future<void>? giveUp,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!_allowed) {
      onApprovalNeeded?.call();
      var gaveUp = false;
      await Future.any([Future<void>.delayed(const Duration(milliseconds: 1600)), ?giveUp?.then((_) => gaveUp = true)]);
      if (gaveUp) throw const WatchException(WatchError.approvalTimeout, 'The watch did not allow this phone');
      _allowed = true;
    }
    return _DemoConnection(address);
  }
}

class _DemoConnection implements WatchConnection {
  _DemoConnection(this.address);

  @override
  final WatchAddress address;

  /// What the demo watch has; [demoServices] starts each demo from [_initial].
  static final _packages = <WatchPackage>[];

  static final _initial = <WatchPackage>[
    for (final (id, name, version) in [
      ('com.watchface.GSHybrid7', 'GS Hybrid 7', '1.0.1'),
      ('com.watchface.GSHybrid6', 'GS Hybrid 6', '1.0.1'),
      ('com.watchface.1224ComboWatch', '12/24 Combo Watch', '1.0.0'),
      ('com.watchface.Active', 'Active', '1.0.3'),
      ('com.watchface.BalloziSKYNOX', 'Ballozi SKYNOX', '1.0.5'),
      ('com.watchface.MD210', 'MD210', '1.0.6'),
      ('com.watchface.MessaRT18', 'Messa_RT18', '1.0.1'),
      ('ru.zakharova.OceanWatchII', 'OceanWatchII', '1.0.1'),
      ('com.watchface.RolmaArmy', 'Rolma Army', '1.0.1'),
    ])
      WatchPackage(
        id: id,
        name: name,
        version: version,
        type: 'tpk',
        origin: PackageOrigin.downloaded,
        kind: PackageKind.watchFace,
      ),
    for (final (id, name, version) in [
      ('2048abcdeg', '2048 for free', '1.0.1'),
      ('org.lechawi.run4gears3free', 'Run4Gear III', '3.1.10'),
      ('net.sweatworks.strava', 'Strava', '2.1.0'),
      ('org.pekdemir.TetriS2', 'TetriS2', '1.2.0'),
      ('com.samsung.compass', 'Compass', '1.0.2'),
    ])
      WatchPackage(
        id: id,
        name: name,
        version: version,
        type: 'wgt',
        origin: PackageOrigin.downloaded,
        kind: PackageKind.app,
      ),
    for (final (id, name) in [
      ('com.samsung.weather', 'Weather'),
      ('com.samsung.alarm-solis', 'Alarm'),
      ('com.samsung.shealth', 'Samsung Health'),
      ('com.samsung.w-music-player', 'Music'),
      ('com.samsung.gallery-solis', 'Gallery'),
    ])
      WatchPackage(
        id: id,
        name: name,
        version: '5.0.78',
        type: 'tpk',
        origin: PackageOrigin.builtIn,
        kind: PackageKind.app,
      ),
  ];

  @override
  WatchIdentity get identity => const WatchIdentity(
    banner: 'device::SM-R800::0',
    model: 'SM-R800',
    tizenVersion: '5.5',
    name: 'Galaxy Watch 46 mm',
  );

  @override
  Future<List<WatchPackage>> listPackages() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return List.of(_packages);
  }

  @override
  Future<WatchStatus> status() async => const WatchStatus(
    batteryPercent: 72,
    charging: false,
    storageFreeBytes: 1717986918,
    storageTotalBytes: 4294967296,
  );

  /// Answers the two questions the app asks the shell, the way a watch would.
  @override
  Future<String> shell(String command) async {
    final pkginfo = RegExp(r'^pkginfo --pkg ([A-Za-z0-9._-]+)$').firstMatch(command);
    if (pkginfo != null) return 'Icon: /opt/usr/globalapps/${pkginfo.group(1)}/shared/res/icon.png\n';
    if (command.startsWith('app_launcher -S')) {
      return '\t appId (PID)\n\t  com.samsung.w-home (3279)\n\t  com.watchface.GSHybrid7 (8561)\n\t  com.samsung.weather-widget (6560)\n';
    }
    final launch = RegExp(r'^app_launcher -s ([A-Za-z0-9._-]+)').firstMatch(command);
    if (launch != null) return '... successfully launched pid = 4242 with debug 0\n';
    if (command.startsWith('paplay ')) {
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      return 'exit=0\n';
    }
    return '';
  }

  @override
  Future<InstallResult> install(File package, {void Function(InstallProgress progress)? onProgress}) async {
    for (var i = 0; i <= 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 70));
      onProgress?.call(Uploading(i * 5, 100));
    }
    for (var p = 0; p <= 100; p += 10) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      onProgress?.call(Installing(p));
    }
    // A package from the demo catalog names itself, so the demo watch can list it or show its new version.
    final lines = package.existsSync() ? await package.readAsLines() : const <String>[];
    if (lines.length == 3 && lines.first == 'demo-package') {
      final (id, version) = (lines[1], lines[2]);
      final at = _packages.indexWhere((p) => p.id == id);
      if (at >= 0) {
        final old = _packages[at];
        _packages[at] = WatchPackage(
          id: id,
          name: old.name,
          version: version,
          type: old.type,
          origin: old.origin,
          kind: old.kind,
        );
      } else {
        final entry = _DemoCatalog._entries.where((e) => e.id == id).firstOrNull;
        _packages.add(
          WatchPackage(
            id: id,
            name: entry?.name ?? id,
            version: version,
            type: 'tpk',
            origin: PackageOrigin.downloaded,
            kind: entry?.kind == CatalogKind.app ? PackageKind.app : PackageKind.watchFace,
          ),
        );
      }
    }
    return const InstallResult(success: true);
  }

  @override
  Future<InstallResult> uninstall(String packageId) async => const InstallResult(success: true);

  @override
  Future<void> upload(
    String remotePath,
    Stream<List<int>> data, {
    required int length,
    int mode = 420,
    void Function(int sent)? onProgress,
  }) async {
    await data.drain<void>();
  }

  @override
  Future<Uint8List> pull(String remotePath, {int maxBytes = 64 << 20, void Function(int received)? onProgress}) async {
    final id = RegExp(r'^/opt/usr/globalapps/([^/]+)/shared/res/icon\.png$').firstMatch(remotePath)?.group(1);
    if (id == null) return Uint8List(0);
    final face = _packages.any((p) => p.id == id && p.kind == PackageKind.watchFace);
    return demoPicture(id, face: face);
  }

  @override
  Future<void> close() async {}
}

class _DemoCatalog implements CatalogApi {
  static const _entries = <CatalogEntry>[
    CatalogEntry(
      id: 'com.watchface.GSHybrid5',
      iconPath: 'demo/com.watchface.GSHybrid5.png',
      name: 'GS Hybrid 5',
      kind: CatalogKind.watchFace,
      verdict: Verdict.installable,
      latestVersion: '1.0.1',
    ),
    CatalogEntry(
      id: '94dUalmnlu',
      iconPath: 'demo/94dUalmnlu.png',
      name: 'GS Weather 8',
      kind: CatalogKind.watchFace,
      verdict: Verdict.installable,
      latestVersion: '1.0.4',
    ),
    CatalogEntry(
      id: 'com.watchface.GSDigital18',
      iconPath: 'demo/com.watchface.GSDigital18.png',
      name: 'GS Digital 18',
      kind: CatalogKind.watchFace,
      verdict: Verdict.installable,
      latestVersion: '1.0.2',
    ),
    CatalogEntry(
      id: 'com.watchface.MD125Hybrid',
      iconPath: 'demo/com.watchface.MD125Hybrid.png',
      name: 'MD125 Hybrid',
      kind: CatalogKind.watchFace,
      verdict: Verdict.installable,
      latestVersion: '1.0.0',
    ),
    CatalogEntry(
      id: 'com.urbandroid.sleep',
      iconPath: 'demo/com.urbandroid.sleep.png',
      name: 'Sleep',
      kind: CatalogKind.app,
      verdict: Verdict.installable,
      latestVersion: '1.4.0',
    ),
    CatalogEntry(
      id: 'com.somyac.maps',
      iconPath: 'demo/com.somyac.maps.png',
      name: 'GPS Navigation',
      kind: CatalogKind.app,
      verdict: Verdict.installable,
      latestVersion: '4.1.1',
    ),
  ];

  @override
  Future<CatalogPage> search({String query = '', CatalogKind? kind, bool installableOnly = true, int page = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final q = query.trim().toLowerCase();
    final items = _entries
        .where((e) => (kind == null || e.kind == kind) && (q.isEmpty || e.name.toLowerCase().contains(q)))
        .toList();
    return CatalogPage(items: items, page: page, hasMore: false, total: items.length);
  }

  /// Packages on the demo watch that the demo archive also has, with its latest version: GS Hybrid 7 has a newer one.
  static const _onWatch = {
    'com.watchface.GSHybrid7': '1.0.2',
    'com.watchface.Active': '1.0.3',
    'net.sweatworks.strava': '2.1.0',
  };

  static String? _latest(String id) => _entries.where((e) => e.id == id).firstOrNull?.latestVersion ?? _onWatch[id];

  @override
  Future<PackageDetails> details(String packageId) async {
    final latest = _latest(packageId);
    if (latest == null) throw const CatalogException('Tizen Archive has no such package', statusCode: 404);
    final entry = _entries.where((e) => e.id == packageId).firstOrNull;
    return PackageDetails(
      id: packageId,
      name: entry?.name ?? packageId,
      description: 'A demo entry. Real details come from Tizen Archive.',
      latestVersion: latest,
      versions: [VersionSummary(version: latest, verdict: entry?.verdict ?? Verdict.installable)],
    );
  }

  @override
  Future<VersionInfo> version(String packageId, [String? version]) async {
    final chosen = version ?? _latest(packageId) ?? '1.0.0';
    return VersionInfo(
      id: packageId,
      version: chosen,
      artifacts: [
        Artifact(downloadUrl: '/demo/$packageId/$chosen', sha256: '', size: 1200000, verdict: Verdict.installable),
      ],
    );
  }

  @override
  ArtifactChoice choose(VersionInfo info) => ArtifactFound(info.artifacts.first);

  @override
  Future<Uint8List> icon(String path) async {
    final entry = _entries.firstWhere(
      (e) => e.iconPath == path,
      orElse: () => throw const CatalogException('No such icon'),
    );
    return demoPicture(entry.id, face: entry.kind == CatalogKind.watchFace);
  }

  @override
  Future<void> download(Artifact artifact, File target, {void Function(int received)? onProgress}) async {
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      onProgress?.call(artifact.size * i ~/ 10);
    }
    final parts = artifact.downloadUrl.split('/');
    await target.writeAsString('demo-package\n${parts[parts.length - 2]}\n${parts.last}\n');
  }
}

class _DemoInspector implements PackageInspector {
  @override
  Future<List<PackageImage>> images(File file, {int maxImages = 12, int maxBytes = 4 << 20}) async => const [];

  @override
  Future<TizenPackageInfo> read(File file) async =>
      const TizenPackageInfo(packageId: 'demo.package', type: 'tpk', version: '1.0.0');

  @override
  Future<SignatureVerdict> signature(File file) async => SignatureVerdict.storeSigned;
}

/// The demo's backups, kept in memory: one made this morning that lacks three of the faces, and any made since.
class _DemoBackups implements BackupService, KnownBackups {
  _DemoBackups() {
    // This morning at 11:47, or yesterday's when it is not yet 11:47: a backup is never in the future.
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, 11, 47);
    if (at.isAfter(now)) at = at.subtract(const Duration(days: 1));
    _add(at, {
      for (final p in _DemoConnection._packages)
        if (p.origin == PackageOrigin.downloaded &&
            !const {'com.watchface.GSHybrid7', 'com.watchface.GSHybrid6', 'com.watchface.MD210'}.contains(p.id))
          p.id,
    });
  }

  final _made = <BackupRecord>[];

  static const _media = [
    BackupMedia(
      path: '/opt/usr/home/owner/media/Music/Morning run.mp3',
      size: 4404019,
      entry: 'media/Music/Morning run.mp3',
    ),
    BackupMedia(
      path: '/opt/usr/home/owner/media/Music/Evening walk.mp3',
      size: 3984588,
      entry: 'media/Music/Evening walk.mp3',
    ),
    BackupMedia(
      path: '/opt/usr/home/owner/media/Pictures/Sunset.png',
      size: 839680,
      entry: 'media/Pictures/Sunset.png',
    ),
    BackupMedia(
      path: '/opt/usr/home/owner/media/Pictures/Screenshot_20261020.png',
      size: 143360,
      entry: 'media/Pictures/Screenshot_20261020.png',
    ),
    BackupMedia(path: '/opt/usr/home/owner/media/Sounds/Alarm.ogg', size: 61440, entry: 'media/Sounds/Alarm.ogg'),
  ];

  @override
  List<BackupRecord> get records => List.unmodifiable(_made);

  /// A face the demo archive does not have, so a demo backup shows what no backup can save.
  static const _notInArchive = 'com.watchface.MD210';

  BackupRecord _add(DateTime at, Set<String> ids, {Set<String> unsaveable = const {}}) {
    final record = BackupRecord(
      file: File('demo-backup-${at.millisecondsSinceEpoch}.twbackup'),
      createdAt: at,
      watch: 'device::SM-R800::0',
      idsWithCopy: ids,
      idsUnsaveable: unsaveable,
      packageCount: ids.length + unsaveable.length,
      mediaCount: _media.length,
    );
    _made.add(record);
    return record;
  }

  @override
  Future<File> create(
    WatchConnection watch,
    Directory folder, {
    Directory? extraPackages,
    required BackupProgress progress,
  }) async {
    final steps = [
      'Reading what the watch has',
      'Saving copies of your faces and apps',
      'Saving your files',
      'Writing the backup',
    ];
    for (var s = 0; s < steps.length; s++) {
      progress.step(steps[s]);
      for (var i = 0; i <= 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        progress.percent(((s + i / 10) / steps.length * 100).round());
      }
    }
    progress.percent(null);
    final downloaded = {
      for (final p in _DemoConnection._packages)
        if (p.origin == PackageOrigin.downloaded) p.id,
    };
    return _add(
      DateTime.now(),
      downloaded.difference(const {_notInArchive}),
      unsaveable: downloaded.intersection(const {_notInArchive}),
    ).file!;
  }

  @override
  Future<BackupContents> open(File backup) async {
    final record = _made.firstWhere(
      (r) => r.file!.path == backup.path,
      orElse: () => throw const FormatException('Not a demo backup'),
    );
    return _DemoContents(record);
  }

  @override
  Future<RestoreResult> restore(
    WatchConnection watch,
    File backup, {
    Set<String> packageIds = const {},
    Set<String> mediaPaths = const {},
    required BackupProgress progress,
  }) async {
    final result = RestoreResult();
    final chosen = _DemoConnection._packages.where((p) => packageIds.contains(p.id)).toList();
    for (var i = 0; i < chosen.length; i++) {
      progress.step('Checking ${chosen[i].name}');
      progress.percent((i / (chosen.length + 1) * 100).round());
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // The demo watch still has everything, as a watch does before a reset.
      result.alreadyThere.add(chosen[i].name);
    }
    if (mediaPaths.isNotEmpty) {
      progress.step('Copying your files');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      result.filesCopied = mediaPaths.length;
    }
    progress.percent(null);
    return result;
  }
}

class _DemoContents implements BackupContents {
  _DemoContents(this._record);

  final BackupRecord _record;

  @override
  File get file => _record.file!;

  @override
  late final BackupManifest manifest = BackupManifest(
    createdAt: _record.createdAt.toIso8601String(),
    watch: _record.watch,
    // A backup holds what was on the watch when it was made: the packages it copied and those it could not.
    packages: [
      for (final p in _DemoConnection._packages)
        if (_record.idsWithCopy.contains(p.id) || _record.idsUnsaveable.contains(p.id))
          BackupPackage(
            id: p.id,
            name: p.name,
            version: p.version,
            type: p.type,
            origin: 'downloaded',
            entry: _record.idsWithCopy.contains(p.id) ? 'packages/${p.name} (${p.id}) v${p.version}.${p.type}' : null,
            entryVersion: p.version,
            source: 'Tizen Archive',
            note: _record.idsWithCopy.contains(p.id) ? null : 'Not in Tizen Archive: a reset removes it for good.',
          ),
    ],
    media: _DemoBackups._media,
  );

  @override
  late final List<BackupItem> items = [
    for (final kind in [PackageKind.watchFace, PackageKind.app])
      for (final p
          in manifest.packages.where((p) => p.entry != null && _kind(p.id) == kind).toList()
            ..sort((a, b) => a.name.compareTo(b.name)))
        BackupItem(package: p, kind: kind),
  ];

  static PackageKind _kind(String id) =>
      _DemoConnection._packages.firstWhere((p) => p.id == id).kind ?? PackageKind.app;

  @override
  Future<Uint8List?> thumbnail(BackupItem item) =>
      demoPicture(item.package.id, face: item.kind == PackageKind.watchFace);

  @override
  Future<List<Uint8List>> pictures(BackupItem item) async => [
    await demoPicture(item.package.id, face: item.kind == PackageKind.watchFace),
  ];

  @override
  Future<Uint8List?> mediaBytes(BackupMedia media, {int maxBytes = 32 << 20}) async => media.path.endsWith('.png')
      ? demoPicture(media.path.contains('Sunset') ? 'com.watchface.BalloziSKYNOX' : 'com.watchface.Active', face: true)
      : null;

  @override
  Future<void> close() async {}
}
