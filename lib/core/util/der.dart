/// A strict reader for DER (the encoding of X.509 certificates and keys) and the few encoders the app's key needs.
///
/// Everything read is untrusted: lengths are checked against the bytes there are, and anything that is not plain
/// DER is a [FormatException].
library;

import 'dart:convert';
import 'dart:typed_data';

/// One DER element: its tag, its content and the bytes of the whole element, as views into the bytes it was read from.
class DerElement {
  DerElement._(this.tag, this.content, this.encoded);

  final int tag;
  final Uint8List content;

  /// Tag, length and content, as they were read.
  final Uint8List encoded;

  static const int integerTag = 0x02;
  static const int bitStringTag = 0x03;
  static const int octetStringTag = 0x04;
  static const int nullTag = 0x05;
  static const int objectIdentifierTag = 0x06;
  static const int sequenceTag = 0x30;
  static const int setTag = 0x31;

  /// Reads the one element that is all of [bytes].
  static DerElement parse(Uint8List bytes) {
    final reader = _Reader(bytes);
    final element = reader.next();
    if (!reader.atEnd) throw const FormatException('Data after the DER element');
    return element;
  }

  /// The elements inside a constructed element (a sequence, a set or a constructed context tag).
  List<DerElement> get children {
    if (tag & 0x20 == 0) throw const FormatException('Not a constructed DER element');
    final reader = _Reader(content);
    return [for (; !reader.atEnd;) reader.next()];
  }

  BigInt get integer {
    _expect(integerTag);
    if (content.isEmpty) throw const FormatException('Empty DER integer');
    var value = BigInt.zero;
    for (final byte in content) {
      value = (value << 8) | BigInt.from(byte);
    }
    // Two's complement: a set top bit makes the number negative
    return content[0] & 0x80 != 0 ? value - (BigInt.one << (8 * content.length)) : value;
  }

  String get objectIdentifier {
    _expect(objectIdentifierTag);
    if (content.isEmpty) throw const FormatException('Empty DER object identifier');
    final parts = <int>[];
    var value = 0;
    for (var i = 0; i < content.length; i++) {
      if (value > 0x00ffffffffffff) throw const FormatException('DER object identifier part too large');
      value = (value << 7) | (content[i] & 0x7f);
      if (content[i] & 0x80 == 0) {
        parts.add(value);
        value = 0;
      } else if (i == content.length - 1) {
        throw const FormatException('Truncated DER object identifier');
      }
    }
    final first = parts.first < 80 ? parts.first ~/ 40 : 2;
    return [first, parts.first - 40 * first, ...parts.skip(1)].join('.');
  }

  /// The bits of a bit string with no unused bits, such as a signature or a public key.
  Uint8List get bitString {
    _expect(bitStringTag);
    if (content.isEmpty || content[0] != 0) throw const FormatException('Unsupported DER bit string');
    return Uint8List.sublistView(content, 1);
  }

  /// A UTCTime or GeneralizedTime, in UTC.
  DateTime get time {
    final text = latin1.decode(content);
    final match = switch (tag) {
      0x17 => RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$').firstMatch(text),
      0x18 => RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\.\d+)?Z$').firstMatch(text),
      _ => throw const FormatException('Not a DER time'),
    };
    if (match == null) throw FormatException('Unsupported DER time', text);
    final numbers = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    // RFC 5280: a two-digit year from 50 on is in the 1900s
    final year = tag == 0x17 ? (numbers[0] >= 50 ? 1900 : 2000) + numbers[0] : numbers[0];
    return DateTime.utc(year, numbers[1], numbers[2], numbers[3], numbers[4], numbers[5]);
  }

  /// The text of a directory string (UTF8String, PrintableString, IA5String, BMPString and the like).
  String get text => switch (tag) {
    0x0c => utf8.decode(content, allowMalformed: true),
    0x12 || 0x13 || 0x14 || 0x16 || 0x1a => latin1.decode(content),
    0x1e => _utf16BigEndian(content),
    0x1c => _utf32BigEndian(content),
    _ => throw const FormatException('Not a DER string'),
  };

  void _expect(int expected) {
    if (tag != expected) throw FormatException('Unexpected DER tag $tag, expected $expected');
  }

  static String _utf16BigEndian(Uint8List bytes) {
    if (bytes.length.isOdd) throw const FormatException('Odd BMPString');
    return String.fromCharCodes([for (var i = 0; i < bytes.length; i += 2) bytes[i] << 8 | bytes[i + 1]]);
  }

  static String _utf32BigEndian(Uint8List bytes) {
    if (bytes.length % 4 != 0) throw const FormatException('Bad UniversalString');
    final codes = [
      for (var i = 0; i < bytes.length; i += 4) bytes[i] << 24 | bytes[i + 1] << 16 | bytes[i + 2] << 8 | bytes[i + 3],
    ];
    if (codes.any((code) => code > 0x10ffff)) throw const FormatException('Bad UniversalString');
    return String.fromCharCodes(codes);
  }
}

class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  int _position = 0;

  bool get atEnd => _position >= _bytes.length;

  DerElement next() {
    final start = _position;
    if (_bytes.length - _position < 2) throw const FormatException('Truncated DER element');
    final tag = _bytes[_position++];
    // X.509 needs no tags beyond 30, so the multi-byte tag form is refused
    if (tag & 0x1f == 0x1f) throw const FormatException('Unsupported DER tag');
    var length = _bytes[_position++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4) throw const FormatException('Unsupported DER length');
      if (_bytes.length - _position < count) throw const FormatException('Truncated DER length');
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _bytes[_position++];
      }
    }
    if (length > _bytes.length - _position) throw const FormatException('DER length beyond the data');
    final content = Uint8List.sublistView(_bytes, _position, _position + length);
    _position += length;
    return DerElement._(tag, content, Uint8List.sublistView(_bytes, start, _position));
  }
}

/// An element with [tag] around [content].
Uint8List derElement(int tag, List<int> content) {
  final length = content.length;
  final header = <int>[tag];
  if (length < 0x80) {
    header.add(length);
  } else {
    final bytes = <int>[];
    for (var value = length; value > 0; value >>= 8) {
      bytes.insert(0, value & 0xff);
    }
    header
      ..add(0x80 | bytes.length)
      ..addAll(bytes);
  }
  return Uint8List.fromList([...header, ...content]);
}

Uint8List derSequence(List<List<int>> elements) =>
    derElement(DerElement.sequenceTag, [for (final element in elements) ...element]);

Uint8List derInteger(BigInt value) {
  if (value.isNegative) throw ArgumentError.value(value, 'value', 'Only non-negative integers are encoded');
  final bytes = <int>[];
  for (var rest = value; rest > BigInt.zero; rest >>= 8) {
    bytes.insert(0, (rest & BigInt.from(0xff)).toInt());
  }
  // A leading zero keeps a set top bit from reading as a sign
  if (bytes.isEmpty || bytes.first & 0x80 != 0) bytes.insert(0, 0);
  return derElement(DerElement.integerTag, bytes);
}

Uint8List derObjectIdentifier(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final content = <int>[];
  for (final part in [40 * parts[0] + parts[1], ...parts.skip(2)]) {
    final groups = <int>[part & 0x7f];
    for (var rest = part >> 7; rest > 0; rest >>= 7) {
      groups.insert(0, 0x80 | (rest & 0x7f));
    }
    content.addAll(groups);
  }
  return derElement(DerElement.objectIdentifierTag, content);
}

Uint8List derNull() => derElement(DerElement.nullTag, const []);

Uint8List derOctetString(List<int> bytes) => derElement(DerElement.octetStringTag, bytes);
