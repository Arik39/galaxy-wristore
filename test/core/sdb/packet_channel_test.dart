import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/sdb/packet_channel.dart';
import 'package:galaxy_wristore/core/sdb/sdb_packet.dart';

/// A channel reading what a loopback server sends: [bytes], then the end of the connection unless [hold].
Future<PacketChannel> _receiving(List<int> bytes, {int maxData = 100, bool hold = false}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = <Socket>[];
  addTearDown(() {
    for (final socket in accepted) {
      socket.destroy();
    }
    return server.close();
  });
  server.listen((socket) async {
    accepted.add(socket);
    socket.add(bytes);
    await socket.flush();
    if (!hold) await socket.close();
  });
  final channel = PacketChannel(await Socket.connect(InternetAddress.loopbackIPv4, server.port), maxData: maxData);
  addTearDown(channel.close);
  return channel;
}

Matcher _fails(ChannelFailure failure) =>
    throwsA(isA<ChannelException>().having((error) => error.failure, 'failure', failure));

void main() {
  test('a packet survives encoding and reading', () async {
    final data = Uint8List.fromList([1, 2, 3, 255]);
    final bytes = SdbPacket(SdbPacket.wrte, 5, 9, data).encode();
    expect(bytes.length, 24 + 4);
    final packet = await (await _receiving(bytes)).read(const Duration(seconds: 5));
    expect([packet.command, packet.arg0, packet.arg1], [SdbPacket.wrte, 5, 9]);
    expect(packet.data, data);
  });

  test('the header has the layout the watch expects', () {
    // CNXN, version 0x01000000, maxdata 0x40000, length 7, byte sum of "host::\0" (0x232), magic = ~CNXN
    const expected =
        '434e584e'
        '00000001'
        '00000400'
        '07000000'
        '32020000'
        'bcb1a7b1'
        '686f73743a3a00';
    final bytes = SdbPacket(SdbPacket.cnxn, 0x01000000, 0x40000, Uint8List.fromList('host::\u0000'.codeUnits)).encode();
    expect(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), expected);
  });

  test('a wrong magic is refused', () async {
    final bytes = SdbPacket(SdbPacket.okay, 1, 2).encode()..[20] = 0;
    final channel = await _receiving(bytes);
    await expectLater(channel.read(const Duration(seconds: 5)), _fails(ChannelFailure.garbage));
  });

  test('a length above the limit is refused before the data arrives', () async {
    final header = SdbPacket(SdbPacket.wrte, 1, 2, Uint8List(50)).encode().sublist(0, 24);
    final channel = await _receiving(header, maxData: 49, hold: true);
    await expectLater(channel.read(const Duration(seconds: 5)), _fails(ChannelFailure.garbage));
  });

  test('a truncated packet ends with the connection', () async {
    final bytes = SdbPacket(SdbPacket.wrte, 1, 2, Uint8List(50)).encode();
    for (final length in [30, 10]) {
      final channel = await _receiving(bytes.sublist(0, length));
      await expectLater(channel.read(const Duration(seconds: 5)), _fails(ChannelFailure.closed));
    }
  });

  test('packets that arrive together are read one by one, and silence times out', () async {
    final bytes = [
      ...SdbPacket(SdbPacket.okay, 1, 2).encode(),
      ...SdbPacket(SdbPacket.wrte, 3, 4, Uint8List.fromList([7, 7])).encode(),
    ];
    final channel = await _receiving(bytes, hold: true);
    expect((await channel.read(const Duration(seconds: 5))).arg0, 1);
    expect((await channel.read(const Duration(seconds: 5))).data, [7, 7]);
    await expectLater(channel.read(const Duration(milliseconds: 200)), _fails(ChannelFailure.timeout));
  });

  test('closing makes a waiting read fail at once', () async {
    final channel = await _receiving(const [], hold: true);
    final read = channel.read(const Duration(seconds: 30));
    channel.close();
    await expectLater(read, _fails(ChannelFailure.closed));
    expect(() => channel.send(SdbPacket(SdbPacket.okay, 1, 2)), throwsA(isA<ChannelException>()));
  });
}
