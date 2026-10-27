import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../api.dart';
import '../util/bytes.dart';
import 'backup_archive.dart';

/// A backup file opened for choosing what to restore. Each read opens the file anew in a background isolate, so
/// pictures load without holding up the screen; nothing stays open between reads.
class ZipBackupContents implements BackupContents {
  ZipBackupContents(this.file, this.manifest, this.items, this._inspector);

  @override
  final File file;
  @override
  final BackupManifest manifest;
  @override
  final List<BackupItem> items;
  final PackageInspector _inspector;
  bool _closed = false;

  @override
  Future<Uint8List?> thumbnail(BackupItem item) async {
    final path = _path;
    return Isolate.run(() => readThumbnail(path, item));
  }

  @override
  Future<List<Uint8List>> pictures(BackupItem item) async {
    final path = _path;
    final temp = await Directory.systemTemp.createTemp('wristore-pictures-');
    try {
      final package = '${temp.path}/package';
      final (fingerprint, extracted) = await Isolate.run(() => readPictureSources(path, item, package));
      final pictures = <Uint8List>[];
      void add(Uint8List bytes) {
        if (!pictures.any((picture) => sameBytes(picture, bytes))) pictures.add(bytes);
      }

      if (fingerprint != null) add(fingerprint);
      if (extracted) {
        try {
          for (final image in await _inspector.images(File(package))) {
            add(image.bytes);
          }
        } on InvalidPackageException {
          // A package file that cannot be read leaves the fingerprint's picture
        }
      }
      return pictures;
    } finally {
      await temp.delete(recursive: true);
    }
  }

  @override
  Future<Uint8List?> mediaBytes(BackupMedia media, {int maxBytes = 32 << 20}) async {
    final path = _path;
    final entry = media.entry;
    return Isolate.run(() => readBackupEntry(path, entry, maxBytes: maxBytes));
  }

  @override
  Future<void> close() async => _closed = true;

  String get _path => _closed ? throw StateError('The backup is closed') : file.path;
}
