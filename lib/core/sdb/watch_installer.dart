import 'dart:io';

import '../api.dart';
import '../util/hashing.dart';
import '../util/text.dart';
import 'pkgcmd_output.dart';
import 'sdb_session.dart';

/// Installs and removes packages through `pkgcmd -w`, the mode that accepts store-signed packages, and reads what the
/// watch has. Shell commands are built only from constants and values checked here, never from text inside a package
/// or from the watch.
class WatchInstaller {
  WatchInstaller(this._service, {this.remoteDir = defaultDir});

  final SdbService _service;

  /// Where a package waits on the watch while it installs.
  final String remoteDir;

  static const String defaultDir = '/home/owner/share/tmp/sdk_tools';

  /// The shell pattern of the names this installer gives packages on the watch.
  static final String _hex16 = '[0-9a-f]' * 16;
  static final RegExp _packageId = RegExp(r'^[A-Za-z0-9._][A-Za-z0-9._-]{0,127}$');
  static final RegExp _listLine = RegExp(r'pkg_type \[(\w+)]\s+pkgid \[([^\]]+)]\s+name \[(.*)]\s+version \[([^\]]*)]');

  /// One line per package under /opt/usr/globalapps: `origin <id> Preload:<0|1> update:<0|1>`; a constant command.
  static const String _originsCommand =
      r'for p in $(ls -1 /opt/usr/globalapps); do '
      r'''echo "origin $p $(pkginfo --pkg $p 2>/dev/null | grep -E '^(Preload|update):' | tr -d ' ' | tr '\n' ' ')"; done''';
  static final RegExp _originLine = RegExp(r'^origin (\S+) ?(.*)$');

  /// For each readable manifest, how often it names a watch application (a native face) or the wearable clock
  /// category (a web face): `<path>:<count>`. Unverified on a watch; a constant command.
  static const String _kindsCommand =
      "grep -H -c -e '<watch-application' -e 'wearable_clock' "
      '/opt/usr/globalapps/*/tizen-manifest.xml /opt/usr/globalapps/*/res/wgt/config.xml /usr/apps/*/tizen-manifest.xml '
      '2>/dev/null';
  static final RegExp _kindLine = RegExp(
    r'^/(?:opt/usr/globalapps|usr/apps)/([^/]+)/(?:tizen-manifest\.xml|res/wgt/config\.xml):(\d+)$',
  );

  /// Whether [text] can be a package id, and so may go into a command: letters, digits, `.`, `_` and `-`, not
  /// starting with `-` and not only dots.
  static bool isPackageId(String text) => _packageId.hasMatch(text) && text.replaceAll('.', '').isNotEmpty;

  /// Sends [file] (a package of [type], `tpk` or `wgt`), installs it and removes the copy from the watch whatever
  /// the outcome.
  Future<InstallResult> install(File file, String type, {void Function(InstallProgress progress)? onProgress}) async {
    if (type != 'tpk' && type != 'wgt') throw ArgumentError.value(type, 'type', 'Not a package type');
    final total = await file.length();
    if (total == 0) throw const InvalidPackageException('The package is empty');
    final remote = '$remoteDir/${(await sha256OfFile(file)).substring(0, 16)}.$type';
    // A copy left behind by an install that was cut off cannot be removed from the phone's side: do it now
    await _service.shell('mkdir -p $remoteDir; rm -f $remoteDir/$_hex16.wgt $remoteDir/$_hex16.tpk');
    try {
      await _service.push(remote, file.openRead(), onProgress: (sent) => onProgress?.call(Uploading(sent, total)));
      onProgress?.call(const Installing(null));
      final output = PkgcmdOutput();
      await _service.shell(
        'pkgcmd -i -t $type -p $remote -w 2>&1',
        onLine: (line) {
          final percent = output.feed(line);
          if (percent != null) onProgress?.call(Installing(percent));
        },
      );
      return output.result();
    } finally {
      try {
        await _service.shell('rm -f $remote');
      } on WatchException {
        // The outcome matters more than the leftover copy, which the next install removes
      }
    }
  }

  /// Every package the watch lists, system ones included (the list does not tell them apart). Names are cleaned for
  /// the screen: one line of at most 200 characters, the id when nothing is left.
  Future<List<WatchPackage>> list() async => [
    for (final line in (await _service.shell('pkgcmd -l 2>&1')).split('\n'))
      if (_listLine.firstMatch(line) case final match?)
        WatchPackage(
          id: match.group(2)!,
          name: cleanLine(match.group(3)!, 200) ?? match.group(2)!,
          version: match.group(4)!,
          type: match.group(1)!,
        ),
  ];

  /// Where the packages installed or updated after the factory (those under /opt/usr/globalapps) came from, by the
  /// package manager's own "Preload" and "update" flags. A package missing from the map is read-only firmware:
  /// [PackageOrigin.builtIn].
  Future<Map<String, PackageOrigin>> origins() async {
    final origins = <String, PackageOrigin>{};
    for (final line in (await _service.shell(_originsCommand)).split('\n')) {
      final match = _originLine.firstMatch(line.trim());
      if (match == null || !isPackageId(match.group(1)!)) continue;
      final flags = match.group(2)!;
      origins[match.group(1)!] = !flags.contains('Preload:1')
          ? PackageOrigin.downloaded
          : flags.contains('update:1')
          ? PackageOrigin.builtInUpdated
          : PackageOrigin.builtIn;
    }
    return origins;
  }

  /// What the packages whose manifest the shell can read are: a watch face when the manifest names a watch application
  /// or the wearable clock category, else an app.
  Future<Map<String, PackageKind>> kinds() async {
    final kinds = <String, PackageKind>{};
    for (final line in (await _service.shell(_kindsCommand)).split('\n')) {
      final match = _kindLine.firstMatch(line.trim());
      if (match == null || !isPackageId(match.group(1)!)) continue;
      final face = (int.tryParse(match.group(2)!) ?? 0) > 0;
      kinds[match.group(1)!] = face || kinds[match.group(1)!] == PackageKind.watchFace
          ? PackageKind.watchFace
          : PackageKind.app;
    }
    return kinds;
  }

  /// Removes the package; its data on the watch is lost. An id that could be an option or a command is refused
  /// before anything is sent.
  Future<InstallResult> remove(String packageId) async {
    if (!isPackageId(packageId)) throw const WatchException(WatchError.refused, 'Not a package id');
    final output = PkgcmdOutput();
    await _service.shell('pkgcmd -u -n $packageId 2>&1', onLine: output.feed);
    return output.result();
  }
}
