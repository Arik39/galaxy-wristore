import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../api.dart';
import '../util/hashing.dart';
import '../util/zip_reader.dart';
import 'signature_inspector.dart';
import 'tizen_manifest.dart';

/// Reads `.tpk` and `.wgt` files: the type comes from the content (a native manifest wins over a web one), never
/// from the file name. The archive is read in a background isolate, so a large package does not hold up the screen.
class ZipPackageInspector implements PackageInspector {
  /// [signatures] holds the certificate authorities that matter and [clock] tells the time certificates expire
  /// against; both can be replaced for tests.
  ZipPackageInspector({this._signatures = const SignatureInspector(), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SignatureInspector _signatures;
  final DateTime Function() _clock;

  @override
  Future<TizenPackageInfo> read(File file) {
    final path = file.path;
    return Isolate.run(() => readPackageInfo(path));
  }

  @override
  Future<List<PackageImage>> images(File file, {int maxImages = 12, int maxBytes = 4 << 20}) {
    final path = file.path;
    return Isolate.run(() => readPackageImages(path, maxImages: maxImages, maxBytes: maxBytes));
  }

  @override
  Future<SignatureVerdict> signature(File file) {
    final path = file.path;
    final signatures = _signatures;
    final now = _clock();
    return Isolate.run(() => signatures.inspect(path, now));
  }
}

const int _maxEntries = 100000;
const int _maxManifestBytes = 1 << 20;
const int _minImageBytes = 1024;
final RegExp _image = RegExp(r'\.(png|jpe?g|webp|gif)$');

/// What the package at [path] says about itself; synchronous. [InvalidPackageException] for anything that is not a
/// readable Tizen package.
TizenPackageInfo readPackageInfo(String path) {
  final zip = _open(path);
  try {
    return _info(zip);
  } finally {
    zip.close();
  }
}

/// The pictures in the package at [path] for a gallery: the icon first (for a watch face often a preview of the whole
/// face), then the largest. Files under 1 KiB (digits, hands, buttons) are left out, a picture stored twice is listed
/// once, and [maxImages] and [maxBytes] bound what is read; a picture over [maxBytes] is skipped, not cut off.
List<PackageImage> readPackageImages(String path, {required int maxImages, required int maxBytes}) {
  final zip = _open(path);
  try {
    String? icon;
    try {
      icon = _info(zip).iconPath;
    } on InvalidPackageException {
      // Pictures without a manifest are still pictures
    }
    final candidates =
        [
          for (final (index, entry) in zip.files.indexed)
            if (entry.size >= _minImageBytes && entry.size <= maxBytes && _image.hasMatch(entry.name.toLowerCase()))
              (index, entry),
        ]..sort((a, b) {
          final byIcon = (a.$2.name == icon ? 0 : 1) - (b.$2.name == icon ? 0 : 1);
          if (byIcon != 0) return byIcon;
          final bySize = b.$2.size.compareTo(a.$2.size);
          return bySize != 0 ? bySize : a.$1.compareTo(b.$1);
        });
    final seen = <String>{};
    final images = <PackageImage>[];
    for (final (_, entry) in candidates) {
      if (images.length >= maxImages) break;
      final Uint8List bytes;
      try {
        bytes = zip.read(entry, maxBytes: maxBytes);
      } on FormatException {
        continue;
      }
      if (seen.add(sha256Hex(bytes))) images.add(PackageImage(entry.name, bytes));
    }
    return images;
  } finally {
    zip.close();
  }
}

ZipReader _open(String path) {
  try {
    return ZipReader.open(path, maxEntries: _maxEntries);
  } on FormatException catch (error) {
    throw InvalidPackageException('Not a valid ZIP archive: ${error.message}');
  } on FileSystemException catch (error) {
    throw InvalidPackageException('Cannot read the archive: ${error.message}');
  }
}

TizenPackageInfo _info(ZipReader zip) {
  final native = zip[nativeManifest];
  if (native != null) return parseNativeManifest(_manifest(zip, native));
  final web = zip[webManifest];
  if (web != null) return parseWebManifest(_manifest(zip, web));
  throw const InvalidPackageException('Neither $nativeManifest nor $webManifest found');
}

Uint8List _manifest(ZipReader zip, ZipEntry entry) {
  if (entry.size > _maxManifestBytes) throw const InvalidPackageException('Manifest is too large');
  try {
    return zip.read(entry, maxBytes: _maxManifestBytes);
  } on FormatException {
    throw const InvalidPackageException('The manifest cannot be read');
  }
}
