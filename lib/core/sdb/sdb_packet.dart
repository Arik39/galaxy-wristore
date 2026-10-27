import 'dart:typed_data';

/// One sdb packet: a 24-byte little-endian header followed by [data].
class SdbPacket {
  SdbPacket(this.command, this.arg0, this.arg1, [Uint8List? data]) : data = data ?? Uint8List(0);

  final int command;
  final int arg0;
  final int arg1;
  final Uint8List data;

  static const int headerSize = 24;
  static const int cnxn = 0x4e584e43;
  static const int auth = 0x48545541;
  static const int open = 0x4e45504f;
  static const int okay = 0x59414b4f;
  static const int clse = 0x45534c43;
  static const int wrte = 0x45545257;

  /// The packet as it goes over the wire: the header carries the data's length, its byte sum and the command's
  /// complement as a check.
  Uint8List encode() {
    var sum = 0;
    for (final byte in data) {
      sum += byte;
    }
    final bytes = Uint8List(headerSize + data.length);
    ByteData.sublistView(bytes)
      ..setUint32(0, command, Endian.little)
      ..setUint32(4, arg0, Endian.little)
      ..setUint32(8, arg1, Endian.little)
      ..setUint32(12, data.length, Endian.little)
      ..setUint32(16, sum & 0xffffffff, Endian.little)
      ..setUint32(20, command ^ 0xffffffff, Endian.little);
    bytes.setRange(headerSize, bytes.length, data);
    return bytes;
  }
}
