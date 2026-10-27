/// The synchronous work on backup files: writing one, and reading its list and entries. A backup can hold hundreds of
/// megabytes, so callers run these in a background isolate.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../api.dart';
import '../util/zip_reader.dart';
import 'backup_format.dart';

/// Writes the backup zip to [target]: the manifest, the report, then every file below [workDirectory] by its path.
void writeBackupArchive(String target, String manifestJson, String reportText, String workDirectory) {
  final names = [
    for (final file in Directory(workDirectory).listSync(recursive: true, followLinks: false).whereType<File>())
      file.path.substring(workDirectory.length + 1).replaceAll(Platform.pathSeparator, '/'),
  ]..sort();
  final output = OutputFileStream(target);
  try {
    final encoder = ZipEncoder()..startEncode(output);
    encoder
      ..add(ArchiveFile.string(manifestEntry, manifestJson))
      ..add(ArchiveFile.string(reportEntry, reportText));
    for (final name in names) {
      final input = InputFileStream('$workDirectory/$name');
      try {
        encoder.add(ArchiveFile.stream(name, input));
      } finally {
        input.closeSync();
      }
    }
    encoder.endEncode();
  } finally {
    output.closeSync();
  }
}

/// The manifest of the backup at [path] and its packages with a copy, as [BackupContents.items] lists them.
(BackupManifest, List<BackupItem>) readBackupIndex(String path) => _withBackup(path, (zip) {
  final manifest = readManifest(zip);
  return (manifest, backupItems(zip, manifest));
});

/// The manifest of the backup at [path] and the names of the files it holds.
(BackupManifest, Set<String>) readBackupManifest(String path) =>
    _withBackup(path, (zip) => (readManifest(zip), {for (final entry in zip.files) entry.name}));

/// The bytes of the entry [name], or null when it is missing or larger than [maxBytes].
Uint8List? readBackupEntry(String path, String name, {required int maxBytes}) => _withBackup(path, (zip) {
  final entry = zip[name];
  if (entry == null || entry.size > maxBytes) return null;
  return zip.read(entry, maxBytes: maxBytes);
});

/// Writes the entry [name] to the file at [target]; false when the backup has no such entry, [FormatException] when it
/// is larger than [maxBytes] or damaged.
bool extractBackupEntry(String path, String name, String target, {required int maxBytes}) => _withBackup(path, (zip) {
  final entry = zip[name];
  if (entry == null) return false;
  if (entry.size > maxBytes) throw FormatException('It is larger than $maxBytes bytes');
  zip.extract(entry, target);
  return true;
});

/// The picture that best shows [item]; null without one.
Uint8List? readThumbnail(String path, BackupItem item) => _withBackup(path, (zip) => _thumbnail(zip, item));

/// The picture the fingerprint of [item] has, and whether its package file was written to [packageTarget]; a package
/// file too large to be one, or damaged, is not.
(Uint8List?, bool) readPictureSources(String path, BackupItem item, String packageTarget) => _withBackup(path, (zip) {
  final name = item.package.entry;
  final package = name == null ? null : zip[name];
  var extracted = false;
  if (package != null && package.size <= maxPackageBytes) {
    try {
      zip.extract(package, packageTarget);
      extracted = true;
    } on FormatException {
      // The fingerprint's picture is still there
    }
  }
  return (_thumbnail(zip, item), extracted);
});

Uint8List? _thumbnail(ZipReader zip, BackupItem item) {
  final name = pictureEntry(zip, item.package.id, item.manifestXml);
  final entry = name == null ? null : zip[name];
  if (entry == null || entry.size < 1 || entry.size > maxPictureBytes) return null;
  return zip.read(entry, maxBytes: maxPictureBytes);
}

T _withBackup<T>(String path, T Function(ZipReader zip) read) {
  final zip = ZipReader.open(path);
  try {
    return read(zip);
  } finally {
    zip.close();
  }
}
