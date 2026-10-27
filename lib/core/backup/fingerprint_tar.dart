import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../util/text.dart';

/// Unpacks the readable files of an app, as the watch's `tar` sent them, into [directory]. Only regular files are
/// written, each only below [directory]: links, devices, absolute names and `..` parts are skipped, so nothing the
/// watch sends can reach outside. Returns how many files were written; [FormatException] when [tar] is not a tar.
int unpackFingerprint(Uint8List tar, String directory) {
  if (tar.isEmpty) return 0;
  final decoder = TarDecoder();
  try {
    decoder.decodeBytes(tar);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Not a tar archive');
  }
  var written = 0;
  for (final entry in decoder.files) {
    final name = _relativeName(entry.filename);
    if (name == null || !const {'0', '', '7'}.contains(entry.typeFlag)) continue;
    try {
      final file = File('$directory/$name');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.contentBytes ?? Uint8List(0));
      written++;
    } on FileSystemException {
      // A name that clashes with another (a file where a folder should be) is left out
    }
  }
  return written;
}

/// [name] as a relative path of plain parts, without a leading `./`; null for anything that could leave the folder.
String? _relativeName(String name) {
  final relative = name.startsWith('./') ? name.substring(2) : name;
  final parts = relative.split('/');
  final plain =
      relative.isNotEmpty &&
      !relative.contains(r'\') &&
      !hasIsoControl(relative) &&
      parts.every((part) => part.isNotEmpty && part != '.' && part != '..');
  return plain ? relative : null;
}
