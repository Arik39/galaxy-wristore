/// The `.twbackup` format 1, shared with the Mac app: a zip with `backup.json` (the [BackupManifest]), `report.txt`,
/// `packages/` (copies of apps and watch faces), `media/` (the user's files) and `fingerprints/<id>/` (what the watch
/// lets be read of every app, and its certificate database).
library;

import 'dart:convert';

import '../api.dart';
import '../catalog/version_compare.dart';
import '../util/text.dart';
import '../util/zip_reader.dart';

/// Where the watch keeps its user's own files: music, pictures, recordings, documents and downloads.
const String mediaRoot = '/opt/usr/home/owner/media';
const String backupExtension = 'twbackup';
const String manifestEntry = 'backup.json';
const String reportEntry = 'report.txt';
const int maxManifestBytes = 5 * 1024 * 1024;
const int maxPictureBytes = 4 * 1024 * 1024;

/// The largest package a backup is trusted to hold, as large as Tizen Archive serves.
const int maxPackageBytes = 512 * 1024 * 1024;

/// The largest file of the user's a restore takes from a backup; a watch has a few gigabytes in all.
const int maxMediaBytes = 2 * 1024 * 1024 * 1024;
const int _maxFingerprintText = 2000000;

/// The part of [path] below the media folder; null for anything else: other folders, hidden files and folders (the
/// watch's logs), `..` parts, commas and control characters. A restore writes only to such paths.
String? mediaRelative(String path) {
  if (!path.startsWith('$mediaRoot/') || hasIsoControl(path) || path.contains(',')) return null;
  final relative = path.substring(mediaRoot.length + 1);
  if (relative.split('/').any((part) => part.isEmpty || part.startsWith('.'))) return null;
  return relative;
}

/// A file name made of [stem] and [extension] that any file system takes: no path separators, colons or control
/// characters, at most 180 characters and 200 bytes, the extension kept.
String safeFileName(String stem, String extension) {
  var name = String.fromCharCodes(
    stem.runes.map((code) => code == 0x2f || code == 0x3a || isIsoControl(code) ? 0x5f : code),
  );
  name = takeRunes(name, 180 - extension.length - 1);
  while (utf8.encode(name).length > 200 - extension.length - 1) {
    name = takeRunes(name, name.runes.length - 1);
  }
  return '$name.$extension';
}

/// How the Mac app writes a package's origin.
String originName(PackageOrigin origin) => switch (origin) {
  PackageOrigin.builtIn => 'built_in',
  PackageOrigin.builtInUpdated => 'built_in_updated',
  PackageOrigin.downloaded => 'downloaded',
};

/// [time] as Java's `LocalDateTime.toString()` writes it without fractions: `2026-10-26T11:47:51`, or
/// `2026-10-26T11:30` when the seconds are zero.
String isoLocalDateTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final minutes =
      '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-${two(time.day)}T${two(time.hour)}:${two(time.minute)}';
  return time.second == 0 ? minutes : '$minutes:${two(time.second)}';
}

/// `Watch backup 2026-10-26 1130.twbackup`.
String backupFileName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'Watch backup ${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}${two(time.minute)}.$backupExtension';
}

/// The manifest as the Mac app writes it: indented, with every field, nulls included.
String encodeManifest(BackupManifest manifest) => const JsonEncoder.withIndent('    ').convert({
  'format': manifest.format,
  'createdAt': manifest.createdAt,
  'watch': manifest.watch,
  'packages': [
    for (final package in manifest.packages)
      {
        'id': package.id,
        'name': package.name,
        'version': package.version,
        'type': package.type,
        'origin': package.origin,
        'entry': package.entry,
        'entryVersion': package.entryVersion,
        'source': package.source,
        'note': package.note,
      },
  ],
  'media': [
    for (final media in manifest.media) {'path': media.path, 'size': media.size, 'entry': media.entry},
  ],
});

/// Reads a manifest; [FormatException] when [text] is not one. Unknown fields are ignored, as by the Mac app.
BackupManifest decodeManifest(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const FormatException('The backup\'s list is not JSON');
  }
  final root = _object(json);
  return BackupManifest(
    format: _optional<int>(root, 'format') ?? 1,
    createdAt: _required<String>(root, 'createdAt'),
    watch: _required<String>(root, 'watch'),
    packages: [
      for (final item in _list(root, 'packages'))
        BackupPackage(
          id: _required<String>(_object(item), 'id'),
          name: _required<String>(_object(item), 'name'),
          version: _required<String>(_object(item), 'version'),
          type: _required<String>(_object(item), 'type'),
          origin: _required<String>(_object(item), 'origin'),
          entry: _optional<String>(_object(item), 'entry'),
          entryVersion: _optional<String>(_object(item), 'entryVersion'),
          source: _optional<String>(_object(item), 'source'),
          note: _optional<String>(_object(item), 'note'),
        ),
    ],
    media: [
      for (final item in _list(root, 'media'))
        BackupMedia(
          path: _required<String>(_object(item), 'path'),
          size: _nonNegative(_required<int>(_object(item), 'size')),
          entry: _required<String>(_object(item), 'entry'),
        ),
    ],
  );
}

/// The manifest inside an opened backup; a file without one is no backup.
BackupManifest readManifest(ZipReader zip) {
  final entry = zip[manifestEntry];
  if (entry == null) throw const FormatException('This is not a watch backup (no $manifestEntry)');
  if (entry.size > maxManifestBytes) throw const FormatException('The backup\'s list is too large');
  return decodeManifest(utf8.decode(zip.read(entry, maxBytes: maxManifestBytes), allowMalformed: true));
}

/// The backup in words: what it holds, what a reset would still take for good, and how to restore it.
String report(BackupManifest manifest) {
  final out = StringBuffer();
  final saved = _sortedByName(manifest.packages.where((package) => package.entry != null));
  final lost = _sortedByName(manifest.packages.where((package) => package.entry == null));
  String note(BackupPackage package) => package.note == null ? '' : '. ${package.note}';
  out
    ..writeln('Galaxy Watch backup, ${manifest.createdAt.replaceAll('T', ' ')}')
    ..writeln('Watch: ${manifest.watch}')
    ..writeln()
    ..writeln('Apps and watch faces a reset removes: ${manifest.packages.length}')
    ..writeln('  With a copy in this backup (${saved.length}):');
  for (final package in saved) {
    out.writeln(
      '    ${package.name} v${package.entryVersion ?? package.version}, from ${package.source}${note(package)}',
    );
  }
  out.writeln('  Without a copy (${lost.length}): a reset removes these for good unless a file of them turns up.');
  for (final package in lost) {
    out.writeln('    ${package.name} (${package.id}) v${package.version}${note(package)}');
  }
  final kilobytes = manifest.media.fold(0, (sum, media) => sum + media.size) ~/ 1024;
  out
    ..writeln()
    ..writeln('Your files from the watch: ${manifest.media.length} ($kilobytes KB)');
  for (final media in manifest.media) {
    out.writeln(
      '    ${media.path.startsWith('$mediaRoot/') ? media.path.substring(mediaRoot.length + 1) : media.path}',
    );
  }
  out
    ..writeln()
    ..writeln('Not in this backup: the data inside apps (the watch does not let it be read) and the watch\'s settings')
    ..writeln('(Samsung\'s own backup in Galaxy Wearable keeps those). A fingerprint of every app is in fingerprints/:')
    ..writeln('a package file found later can be checked against it.')
    ..writeln()
    ..writeln('To restore: open this file in Galaxy Wristore (or in Tizen Watch on a Mac) and choose what to put back.')
    ..writeln('Package files you find later: add them as your own package files to the next backup.');
  return out.toString();
}

/// What a restore installs: the packages with a copy, unless the watch already has that version or a newer one.
class RestorePlan {
  const RestorePlan(this.install, this.alreadyThere, this.noCopy);

  final List<BackupPackage> install;
  final List<BackupPackage> alreadyThere;
  final List<BackupPackage> noCopy;
}

/// The plan for [packages] on a watch with the [installed] versions, by package id.
RestorePlan planInstalls(List<BackupPackage> packages, Map<String, String> installed) {
  final install = <BackupPackage>[];
  final alreadyThere = <BackupPackage>[];
  for (final package in packages.where((package) => package.entry != null)) {
    final there = installed[package.id];
    final current = there != null && VersionCompare.compare(there, package.entryVersion ?? package.version) >= 0;
    (current ? alreadyThere : install).add(package);
  }
  return RestorePlan(install, alreadyThere, [
    for (final package in packages)
      if (package.entry == null) package,
  ]);
}

/// Files of a watch face: its hands and its always-on (ambient) pictures, as the package's signed file list names them.
final RegExp _faceFiles = RegExp(
  r'__AMBIENT__|hour[-_]?hand|minute[-_]?hand|hands_(hr|min)|aod_',
  caseSensitive: false,
);

/// A watch face or an app, from what a backup's fingerprint has of the package: its manifest when the watch let it be
/// read, else the files its author signature lists.
PackageKind packageKind(String id, String? manifestXml, [String? signatureXml]) {
  if ((manifestXml?.contains('<watch-application') ?? false) || id.startsWith('com.watchface.')) {
    return PackageKind.watchFace;
  }
  if (manifestXml == null && signatureXml != null && _faceFiles.hasMatch(signatureXml)) return PackageKind.watchFace;
  return PackageKind.app;
}

/// A text file of the backup's fingerprint of [id], when the watch let it be read.
String? fingerprintText(ZipReader zip, String id, String name) {
  final entry = zip['fingerprints/$id/$name'];
  if (entry == null || entry.size > _maxFingerprintText) return null;
  return utf8.decode(zip.read(entry, maxBytes: _maxFingerprintText), allowMalformed: true);
}

/// The name inside the backup of the picture that best shows a package: the icon its manifest names (for a watch face,
/// a preview of the whole face), else the first picture of its fingerprint.
String? pictureEntry(ZipReader zip, String id, String? manifestXml) {
  final folder = 'fingerprints/$id/shared/res/';
  final icon = RegExp(r'<icon>\s*([^<]+?)\s*</icon>').firstMatch(manifestXml ?? '')?.group(1);
  if (icon != null && zip['$folder$icon'] != null) return '$folder$icon';
  final pictures = [
    for (final entry in zip.files)
      if (entry.name.startsWith(folder) &&
          (entry.name.toLowerCase().endsWith('.png') || entry.name.toLowerCase().endsWith('.jpg')))
        entry.name,
  ]..sort();
  return pictures.firstOrNull;
}

/// The packages of a backup with a copy, with what their fingerprints tell: watch faces first, then by name.
List<BackupItem> backupItems(ZipReader zip, BackupManifest manifest) {
  final items = [
    for (final package in manifest.packages)
      if (package.entry != null)
        _item(
          package,
          fingerprintText(zip, package.id, 'tizen-manifest.xml'),
          () => fingerprintText(zip, package.id, 'author-signature.xml'),
        ),
  ];
  return [
    for (final (_, item)
        in items.indexed.toList()..sort((a, b) {
          final byKind = (a.$2.kind == PackageKind.watchFace ? 0 : 1) - (b.$2.kind == PackageKind.watchFace ? 0 : 1);
          if (byKind != 0) return byKind;
          final byName = a.$2.package.name.toLowerCase().compareTo(b.$2.package.name.toLowerCase());
          return byName != 0 ? byName : a.$1.compareTo(b.$1);
        }))
      item,
  ];
}

BackupItem _item(BackupPackage package, String? manifestXml, String? Function() signatureXml) => BackupItem(
  package: package,
  kind: packageKind(package.id, manifestXml, manifestXml == null ? signatureXml() : null),
  manifestXml: manifestXml,
);

List<BackupPackage> _sortedByName(Iterable<BackupPackage> packages) => [
  for (final (_, package)
      in packages.indexed.toList()..sort((a, b) {
        final byName = a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
        return byName != 0 ? byName : a.$1.compareTo(b.$1);
      }))
    package,
];

Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : throw const FormatException('Unexpected backup list');

List<Object?> _list(Map<String, Object?> json, String key) =>
    json[key] is List<Object?> ? json[key]! as List<Object?> : throw FormatException('The backup list has no $key');

T _required<T>(Map<String, Object?> json, String key) =>
    json[key] is T && json[key] != null ? json[key] as T : throw FormatException('The backup list has no $key');

T? _optional<T>(Map<String, Object?> json, String key) => switch (json[key]) {
  null => null,
  final T value => value,
  _ => throw FormatException('The backup list has an unexpected $key'),
};

int _nonNegative(int value) =>
    value >= 0 ? value : throw const FormatException('A negative file size in the backup list');
