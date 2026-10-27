import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/util/zip_reader.dart';

import '../support/zips.dart';

/// The offsets of the central directory headers in [zip].
List<int> _centralHeaders(Uint8List zip) => [
  for (var i = 0; i + 4 <= zip.length; i++)
    if (zip[i] == 0x50 && zip[i + 1] == 0x4b && zip[i + 2] == 0x01 && zip[i + 3] == 0x02) i,
];

/// The offset of the end record in [zip], which has no comment.
int _end(Uint8List zip) => zip.length - 22;

void _setUint16(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint16(offset, value, Endian.little);

void _setUint32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);

/// [zip] ended the zip64 way: a zip64 end record and its locator before an end record whose fields are all saturated.
Uint8List _asZip64(Uint8List zip) {
  final end = _end(zip);
  final view = ByteData.sublistView(zip);
  final entries = view.getUint16(end + 10, Endian.little);
  final record = ByteData(56)
    ..setUint32(0, 0x06064b50, Endian.little)
    ..setUint64(4, 44, Endian.little)
    ..setUint16(12, 45, Endian.little)
    ..setUint16(14, 45, Endian.little)
    ..setUint64(24, entries, Endian.little)
    ..setUint64(32, entries, Endian.little)
    ..setUint64(40, view.getUint32(end + 12, Endian.little), Endian.little)
    ..setUint64(48, view.getUint32(end + 16, Endian.little), Endian.little);
  final locator = ByteData(20)
    ..setUint32(0, 0x07064b50, Endian.little)
    ..setUint64(8, end, Endian.little)
    ..setUint32(16, 1, Endian.little);
  final last = Uint8List.fromList(zip.sublist(end));
  _setUint16(last, 8, 0xffff);
  _setUint16(last, 10, 0xffff);
  _setUint32(last, 12, 0xffffffff);
  _setUint32(last, 16, 0xffffffff);
  return Uint8List.fromList([
    ...zip.sublist(0, end),
    ...record.buffer.asUint8List(),
    ...locator.buffer.asUint8List(),
    ...last,
  ]);
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('zip-reader-test-'));
  tearDown(() => dir.delete(recursive: true));

  var count = 0;
  File file(List<int> bytes) => File('${dir.path}/z${count++}.zip')..writeAsBytesSync(bytes);

  Uint8List archive(List<ArchiveFile> files) {
    final archive = Archive();
    files.forEach(archive.add);
    return ZipEncoder().encodeBytes(archive);
  }

  ZipReader open(List<int> bytes, {int maxEntries = 100000}) {
    final zip = ZipReader.open(file(bytes).path, maxEntries: maxEntries);
    addTearDown(zip.close);
    return zip;
  }

  test('entries are read and extracted by name, directories left out', () {
    final zip = open(
      archive([
        ArchiveFile.directory('res/'),
        ArchiveFile.string('res/a.txt', 'hello'),
        ArchiveFile.bytes('b.bin', List.filled(70000, 3)),
        ArchiveFile.noCompress('c.bin', 3, [1, 2, 3]),
      ]),
    );
    expect(zip.files.map((entry) => entry.name), ['res/a.txt', 'b.bin', 'c.bin']);
    expect(zip['res/'], isNull);
    expect(String.fromCharCodes(zip.read(zip['res/a.txt']!, maxBytes: 100)), 'hello');
    expect(zip.read(zip['c.bin']!, maxBytes: 3), [1, 2, 3]);
    expect(() => zip.read(zip['b.bin']!, maxBytes: 69999), throwsFormatException);
    final target = '${dir.path}/b.out';
    zip.extract(zip['b.bin']!, target);
    expect(File(target).readAsBytesSync(), List.filled(70000, 3));
  });

  test('archives written as a stream (sizes after the data, as Java writes them) and zip64 ones are read', () async {
    final source = File('${dir.path}/source.bin')..writeAsBytesSync(List.generate(100000, (i) => i % 7));
    final input = InputFileStream(source.path);
    final output = OutputMemoryStream();
    final encoder = ZipEncoder()..startEncode(output);
    encoder
      ..add(ArchiveFile.stream('Музыка/streamed.bin', input))
      ..endEncode();
    input.closeSync();
    final streamed = output.getBytes();
    for (final bytes in [streamed, _asZip64(streamed)]) {
      final zip = open(bytes);
      expect(zip.read(zip['Музыка/streamed.bin']!, maxBytes: 1 << 20), source.readAsBytesSync());
    }
  });

  test('a large file that is not a zip is refused without being walked', () {
    final random = Random(1);
    final junk = List.generate(3 << 20, (_) => random.nextInt(256));
    final started = DateTime.now();
    expect(() => ZipReader.open(file(junk).path), throwsFormatException);
    expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 2)));
    expect(() => ZipReader.open(file(const [1, 2, 3]).path), throwsFormatException);
    expect(() => ZipReader.open('${dir.path}/missing'), throwsA(isA<FileSystemException>()));
  });

  test('more entries than allowed are refused, whatever the end record claims', () {
    final bytes = zipBytes({for (var i = 0; i < 20; i++) 'f$i': 'x'});
    expect(() => open(bytes, maxEntries: 19), throwsFormatException);
    open(bytes, maxEntries: 20);
    _setUint16(bytes, _end(bytes) + 8, 1);
    _setUint16(bytes, _end(bytes) + 10, 1);
    expect(() => open(bytes, maxEntries: 19), throwsFormatException);
  });

  test('links are left out unread', () {
    final bytes = archive([
      ArchiveFile.bytes('link', List.filled(5000, 1))..mode = 0xa1ff,
      ArchiveFile.string('file.txt', 'ok'),
    ]);
    // Made on Unix, so the mode means a symbolic link
    bytes[_centralHeaders(bytes).first + 5] = 3;
    final zip = open(bytes);
    expect(zip.files.map((entry) => entry.name), ['file.txt']);
  });

  test('an entry that is damaged, holds more than it declares or cannot be read is refused when read', () {
    /// One deflated entry, its directory header changed by [change].
    Uint8List patched(void Function(Uint8List bytes, int header) change) {
      final bytes = zipBytes({'a.txt': 'x' * 1000});
      change(bytes, _centralHeaders(bytes).single);
      return bytes;
    }

    final cases = <String, Uint8List>{
      'smaller size declared': patched((bytes, header) => _setUint32(bytes, header + 24, 10)),
      'larger size declared': patched((bytes, header) => _setUint32(bytes, header + 24, 2000)),
      'wrong checksum': patched((bytes, header) => _setUint32(bytes, header + 16, 1)),
      'encrypted': patched((bytes, header) => _setUint16(bytes, header + 8, 1)),
      'unknown method': patched((bytes, header) => _setUint16(bytes, header + 10, 12)),
      'no local header': patched((bytes, header) => _setUint32(bytes, header + 42, 100)),
    };
    for (final MapEntry(key: name, value: bytes) in cases.entries) {
      final zip = open(bytes);
      expect(() => zip.read(zip['a.txt']!, maxBytes: 100000), throwsFormatException, reason: name);
    }
  });

  test('a directory beyond the file or cut short is refused when opening', () {
    final moved = zipBytes({'a.txt': 'x'});
    _setUint32(moved, _end(moved) + 16, moved.length);
    expect(() => open(moved), throwsFormatException);
    final cut = zipBytes({'a.txt': 'x', 'b.txt': 'y'});
    _setUint16(cut, _centralHeaders(cut).last + 28, 0xffff);
    expect(() => open(cut), throwsFormatException);
  });
}
