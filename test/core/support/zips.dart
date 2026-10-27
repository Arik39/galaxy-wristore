import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A zip holding [entries] in order; a value is a [String] (written as UTF-8) or bytes.
Uint8List zipBytes(Map<String, Object> entries) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in entries.entries) {
    archive.add(ArchiveFile.bytes(key, value is String ? utf8.encode(value) : value as List<int>));
  }
  return ZipEncoder().encodeBytes(archive);
}

var _counter = 0;

/// Writes [zipBytes] of [entries] to a new file in [directory].
File writeZip(Directory directory, Map<String, Object> entries, {String? name}) =>
    File('${directory.path}/${name ?? 'zip-${_counter++}.bin'}')..writeAsBytesSync(zipBytes(entries));

const String tpkManifest = '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns="http://tizen.org/ns/packages" api-version="2.3.1.2" package="com.example.watch" version="1.2.3">
  <watch-application ambient-support="true" appid="com.example.watch" exec="com.example.watch">
    <label xml:lang="ru-ru">Циферблат</label>
    <label> Example Face </label>
    <icon>face.png</icon>
  </watch-application>
</manifest>''';

const String wgtConfig = '''<?xml version="1.0" encoding="UTF-8"?>
<widget xmlns="http://www.w3.org/ns/widgets" xmlns:tizen="http://tizen.org/ns/widgets" id="http://x/Y" version="2.0.1">
  <tizen:application id="AbCdEfGhIj.Calc" package="AbCdEfGhIj" required_version="2.3"/>
  <content src="index.html"/>
  <icon src="img/icon.png" height="117" width="117"/>
  <name xml:lang="ru">Калькулятор</name>
  <name>Calc</name>
</widget>''';

/// A native package manifest for [id] at [version].
String nativeManifestFor(String id, String version, {bool face = true, String icon = 'icon.png'}) =>
    '<manifest xmlns="http://tizen.org/ns/packages" package="$id" version="$version">'
    '<${face ? 'watch' : 'ui'}-application appid="$id"><label>$id</label><icon>$icon</icon></${face ? 'watch' : 'ui'}-application>'
    '</manifest>';
