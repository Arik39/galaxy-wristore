/// Reading entries of an untrusted zip file (a package or a backup) by name, with bounds on what is read.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// One file of a [ZipReader]; [size] is what the archive declares, which reading never goes past.
class ZipEntry {
  ZipEntry._(this.name, this.size, this._compressedSize, this._method, this._flags, this._crc32, this._localOffset);

  final String name;
  final int size;
  final int _compressedSize;
  final int _method;
  final int _flags;
  final int _crc32;
  final int _localOffset;
}

/// A zip file opened for reading. Opening reads only the central directory, which is bounded, and an entry is read only
/// when asked for, so nothing an archive declares makes the reader allocate more than its caller allows. Stored and
/// deflated entries are read and checked against their declared size and CRC-32; anything else (encryption, other
/// compression methods, damage) is a [FormatException]. It works synchronously: large reads belong in a background
/// isolate. [close] releases the file.
class ZipReader {
  ZipReader._(this._file, this._length, this._files);

  final RandomAccessFile _file;
  final int _length;
  final Map<String, ZipEntry> _files;

  static const int _endRecordSize = 22;
  static const int _headerSize = 46;
  static const int _localHeaderSize = 30;
  static const int _maxDirectoryBytes = 32 << 20;
  static const int _chunk = 64 * 1024;

  /// Opens the zip at [path]; throws [FormatException] for anything that is not a readable zip of at most [maxEntries]
  /// entries, and [FileSystemException] when the file cannot be read.
  static ZipReader open(String path, {int maxEntries = 100000}) {
    final file = File(path).openSync();
    try {
      final length = file.lengthSync();
      return ZipReader._(file, length, _readDirectory(file, length, maxEntries));
    } catch (_) {
      file.closeSync();
      rethrow;
    }
  }

  /// The files of the archive (directories and links left out), in the order of its directory.
  Iterable<ZipEntry> get files => _files.values;

  /// The file called exactly [name], or null.
  ZipEntry? operator [](String name) => _files[name];

  /// The content of [entry]; [FormatException] when it is larger than [maxBytes] or cannot be read.
  Uint8List read(ZipEntry entry, {required int maxBytes}) {
    if (entry.size > maxBytes) throw FormatException('${entry.name} is larger than $maxBytes bytes');
    final bytes = BytesBuilder(copy: false);
    _inflate(entry, bytes.add);
    return bytes.takeBytes();
  }

  /// Writes the content of [entry] to the file at [path]; the caller bounds [ZipEntry.size] first.
  void extract(ZipEntry entry, String path) {
    final output = File(path).openSync(mode: FileMode.writeOnly);
    try {
      _inflate(entry, output.writeFromSync);
    } finally {
      output.closeSync();
    }
  }

  void close() => _file.closeSync();

  /// Hands the content of [entry] to [output] piece by piece, at most its declared size, then checks it is all there.
  void _inflate(ZipEntry entry, void Function(List<int> bytes) output) {
    if (entry._flags & 1 != 0) throw FormatException('${entry.name} is encrypted');
    final header = _readAt(_file, entry._localOffset, _localHeaderSize);
    if (_uint32(header, 0) != 0x04034b50) throw FormatException('${entry.name} has no local header');
    // The local header's own name and extra field are skipped unread: the directory's are the ones that count
    final start = entry._localOffset + _localHeaderSize + _uint16(header, 26) + _uint16(header, 28);
    if (start + entry._compressedSize > _length) throw FormatException('${entry.name} is cut off');
    var written = 0;
    var crc = 0;
    void emit(List<int> bytes) {
      written += bytes.length;
      if (written > entry.size) throw FormatException('${entry.name} holds more than it declares');
      crc = getCrc32(bytes, crc);
      output(bytes);
    }

    final inflater = switch (entry._method) {
      0 => null,
      8 => ZLibDecoder(raw: true).startChunkedConversion(_Emitter(emit)),
      _ => throw FormatException('${entry.name} uses an unsupported compression method'),
    };
    _file.setPositionSync(start);
    for (var left = entry._compressedSize; left > 0;) {
      final chunk = _file.readSync(min(left, _chunk));
      if (chunk.isEmpty) throw FormatException('${entry.name} is cut off');
      left -= chunk.length;
      if (inflater == null) {
        emit(chunk);
      } else {
        inflater.add(chunk);
      }
    }
    inflater?.close();
    // A deflate stream that stops short ends without an error, so the size and checksum tell
    if (written != entry.size || crc != entry._crc32) throw FormatException('${entry.name} is damaged');
  }

  static Map<String, ZipEntry> _readDirectory(RandomAccessFile file, int length, int maxEntries) {
    if (length < _endRecordSize) throw const FormatException('Not a zip archive');
    // The end record is the last thing in a zip, followed only by a comment of at most 64 KiB
    final tailLength = min(length, _endRecordSize + 0xffff);
    final tailStart = length - tailLength;
    final tail = _readAt(file, tailStart, tailLength);
    var end = -1;
    for (var i = tail.length - _endRecordSize; i >= 0 && end < 0; i--) {
      if (_uint32(tail, i) == 0x06054b50) end = i;
    }
    if (end < 0) throw const FormatException('Not a zip archive');
    var directorySize = _uint32(tail, end + 12);
    var directoryOffset = _uint32(tail, end + 16);
    if (_uint16(tail, end + 10) == 0xffff || directorySize == 0xffffffff || directoryOffset == 0xffffffff) {
      // Zip64: the real values are in the zip64 end record, which a locator just before this one points to
      final locator = tailStart + end - 20;
      if (locator < 0) throw const FormatException('Damaged zip64 archive');
      final locatorBytes = _readAt(file, locator, 20);
      final recordOffset = _uint64(locatorBytes, 8);
      if (_uint32(locatorBytes, 0) != 0x07064b50 || recordOffset < 0 || recordOffset > locator - 56) {
        throw const FormatException('Damaged zip64 archive');
      }
      final record = _readAt(file, recordOffset, 56);
      if (_uint32(record, 0) != 0x06064b50) throw const FormatException('Damaged zip64 archive');
      directorySize = _uint64(record, 40);
      directoryOffset = _uint64(record, 48);
    }
    if (directorySize < 0 ||
        directorySize > _maxDirectoryBytes ||
        directoryOffset < 0 ||
        directoryOffset > length - directorySize) {
      throw const FormatException('Damaged zip directory');
    }
    final directory = _readAt(file, directoryOffset, directorySize);
    final files = <String, ZipEntry>{};
    var count = 0;
    for (var at = 0; directory.length - at >= _headerSize && _uint32(directory, at) == 0x02014b50;) {
      if (++count > maxEntries) throw const FormatException('Too many entries in the archive');
      final nameLength = _uint16(directory, at + 28);
      final extraLength = _uint16(directory, at + 30);
      final next = at + _headerSize + nameLength + extraLength + _uint16(directory, at + 32);
      if (next > directory.length) throw const FormatException('Damaged zip directory');
      var compressed = _uint32(directory, at + 20);
      var size = _uint32(directory, at + 24);
      var local = _uint32(directory, at + 42);
      if (compressed == 0xffffffff || size == 0xffffffff || local == 0xffffffff) {
        // The zip64 extra field holds the values that did not fit, in this order
        final values = _zip64Values(Uint8List.sublistView(directory, at + _headerSize + nameLength, next));
        var used = 0;
        int take() => used < values.length ? values[used++] : throw const FormatException('Damaged zip64 entry');
        if (size == 0xffffffff) size = take();
        if (compressed == 0xffffffff) compressed = take();
        if (local == 0xffffffff) local = take();
      }
      if (compressed < 0 || size < 0 || local < 0 || local > length) throw const FormatException('Damaged zip entry');
      final name = _name(Uint8List.sublistView(directory, at + _headerSize, at + _headerSize + nameLength));
      // Made on Unix (the upper byte of "version made by" is 3), the upper half of the attributes is the file's mode
      final link = directory[at + 5] == 3 && (_uint32(directory, at + 38) >> 16) & 0xf000 == 0xa000;
      if (!name.endsWith('/') && !link) {
        files[name] = ZipEntry._(
          name,
          size,
          compressed,
          _uint16(directory, at + 10),
          _uint16(directory, at + 8),
          _uint32(directory, at + 16),
          local,
        );
      }
      at = next;
    }
    return files;
  }

  /// The 8-byte values of the zip64 record (id 1) in an [extra] field; none without one.
  static List<int> _zip64Values(Uint8List extra) {
    for (var at = 0; extra.length - at >= 4;) {
      final id = _uint16(extra, at);
      final size = _uint16(extra, at + 2);
      if (extra.length - at - 4 < size) break;
      if (id == 1) return [for (var i = 0; i + 8 <= size; i += 8) _uint64(extra, at + 4 + i)];
      at += 4 + size;
    }
    return const [];
  }

  /// Names are UTF-8, as Java and most tools write them; a name that is not is read as Latin-1.
  static String _name(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static Uint8List _readAt(RandomAccessFile file, int position, int count) {
    file.setPositionSync(position);
    final bytes = file.readSync(count);
    if (bytes.length != count) throw const FormatException('Truncated zip archive');
    return bytes;
  }

  static int _uint16(Uint8List bytes, int offset) => bytes[offset] | bytes[offset + 1] << 8;

  static int _uint32(Uint8List bytes, int offset) => _uint16(bytes, offset) | _uint16(bytes, offset + 2) << 16;

  /// A little-endian 64-bit value; one with the top bit set comes out negative, which the callers refuse.
  static int _uint64(Uint8List bytes, int offset) => _uint32(bytes, offset) | _uint32(bytes, offset + 4) << 32;
}

/// Passes what the inflater produces on to a function.
class _Emitter implements Sink<List<int>> {
  _Emitter(this._emit);

  final void Function(List<int> bytes) _emit;

  @override
  void add(List<int> data) => _emit(data);

  @override
  void close() {}
}
