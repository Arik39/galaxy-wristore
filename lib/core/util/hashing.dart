/// SHA-256 over bytes and files, as lowercase hex.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// SHA-256 of [bytes] as lowercase hex.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// SHA-256 of what is fed to it piece by piece, for data too large to hold at once.
class Sha256Builder {
  Sha256Builder() {
    _input = sha256.startChunkedConversion(_output);
  }

  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;

  void add(List<int> bytes) => _input.add(bytes);

  /// The digest as lowercase hex; nothing may be added afterwards.
  String finish() {
    _input.close();
    return _output.digest.toString();
  }
}

/// SHA-256 of the content of [file] as lowercase hex, read in pieces.
Future<String> sha256OfFile(File file) async {
  final builder = Sha256Builder();
  await for (final chunk in file.openRead()) {
    builder.add(chunk);
  }
  return builder.finish();
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
