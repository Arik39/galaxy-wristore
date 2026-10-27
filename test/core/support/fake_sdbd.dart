import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:galaxy_wristore/core/sdb/sdb_packet.dart';

/// A just-enough sdbd on loopback: authorization with key confirmation, `shell:` and `sync:` services. Written from
/// the protocol, not from the client: it checks signatures and reads public keys with its own arithmetic.
class FakeSdbd {
  FakeSdbd._(this._server, this.maxData) {
    _server.listen((socket) {
      _sockets.add(socket);
      socket.done.ignore();
      _serve(socket).catchError((Object _) {}).whenComplete(socket.destroy);
    });
  }

  static Future<FakeSdbd> start({int maxData = 262144}) async =>
      FakeSdbd._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), maxData);

  final ServerSocket _server;
  final int maxData;
  final List<Socket> _sockets = [];

  int get port => _server.port;

  /// The watch closes every connection at once, as when another host is connected.
  bool busy = false;

  /// A busy watch resets the connection instead of closing it politely.
  bool busyReset = false;

  /// The watch accepts connections but never answers, as with Debugging off.
  bool silent = false;

  /// Something that is not sdb answers.
  bool sendGarbage = false;

  /// The user taps Allow on the watch; false means Deny (the watch closes the connection).
  bool allowNewKeys = true;

  /// How long the user takes to confirm.
  Duration confirmDelay = Duration.zero;

  /// Sends the last packet of a closed sync service again, as the real watch does.
  bool staleClose = false;

  String banner = 'device::SM-R800::0';

  int confirmations = 0;

  /// Shell output by exact command, and for commands not there, by how the command starts.
  final Map<String, String> shells = {};
  final Map<String, String> shellsStartingWith = {};
  int shellChunk = 1 << 30;
  final Map<String, Uint8List> files = {};

  /// Paths whose upload the watch refuses at the end.
  final Set<String> refuseUploads = {};

  /// Paths the watch cannot open for writing: it fails as soon as the send begins, as sdbd's sync service does.
  final Set<String> failAtSend = {};

  /// For a file read: the size of a DATA frame, and the size of the packets the frames are cut into.
  int recvFrame = 4096;
  int recvChunk = 777;
  final Map<String, int> modes = {};
  final List<String> commands = [];
  final List<int> writeSizes = [];
  final List<String> keyNames = [];
  final List<(BigInt, BigInt)> _trusted = [];

  Future<void> close() async {
    await _server.close();
    for (final socket in _sockets) {
      socket.destroy();
    }
  }

  Future<void> _serve(Socket socket) async {
    if (busy) {
      if (busyReset) {
        // SO_LINGER with a zero timeout: closing sends a reset
        final soLinger = Platform.isMacOS || Platform.isIOS ? 0x80 : 13;
        socket.setRawOption(
          RawSocketOption(RawSocketOption.levelSocket, soLinger, Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0])),
        );
      }
      return;
    }
    final reader = _Reader(socket);
    if (silent) {
      await reader.next();
      await reader.untilClosed();
      return;
    }
    void send(int command, int arg0, int arg1, [List<int> data = const []]) =>
        socket.add(SdbPacket(command, arg0, arg1, Uint8List.fromList(data)).encode());
    if (sendGarbage) {
      socket.add(List.filled(24, 7));
      await socket.flush();
      return;
    }
    final hello = await reader.next();
    if (hello == null || hello.command != SdbPacket.cnxn || !latin1.decode(hello.data).startsWith('host::')) return;
    var token = [for (var i = 0; i < 20; i++) (i * 13 + 1) & 0xff];
    send(SdbPacket.auth, 1, 0, token);
    while (true) {
      final packet = await reader.next();
      if (packet == null || packet.command != SdbPacket.auth) return;
      if (packet.arg0 == 2) {
        if (_trusted.any((key) => _verify(key, token, packet.data))) {
          send(SdbPacket.cnxn, 0x01000000, maxData, ascii.encode('$banner\u0000'));
          break;
        }
        token = [for (var i = 0; i < 20; i++) (i * 7 + 3) & 0xff];
        send(SdbPacket.auth, 1, 0, token);
      } else if (packet.arg0 == 3) {
        confirmations++;
        if (!allowNewKeys) return;
        await Future<void>.delayed(confirmDelay);
        final (key, name) = _parseKey(packet.data);
        keyNames.add(name);
        _trusted.add(key);
        send(SdbPacket.cnxn, 0x01000000, maxData, ascii.encode('$banner\u0000'));
        break;
      } else {
        return;
      }
    }
    await _services(reader, send);
  }

  Future<void> _services(_Reader reader, void Function(int, int, int, [List<int>]) send) async {
    var remoteIds = 100;
    String? syncPath;
    final received = BytesBuilder();
    var syncRemote = -1;
    var syncLocal = -1;
    while (true) {
      final packet = await reader.next();
      if (packet == null) return;
      if (packet.command == SdbPacket.open) {
        final service = utf8.decode(packet.data).replaceAll('\u0000', '');
        final remote = ++remoteIds;
        send(SdbPacket.okay, remote, packet.arg0);
        if (service.startsWith('shell:')) {
          final command = service.substring('shell:'.length);
          commands.add(command);
          final answer =
              shells[command] ??
              shellsStartingWith.entries.where((entry) => command.startsWith(entry.key)).firstOrNull?.value;
          final out = utf8.encode(answer ?? '');
          // Like a real watch, never more in one packet than the connection allows
          final chunk = shellChunk < maxData ? shellChunk : maxData;
          for (var offset = 0; offset < out.length; offset += chunk) {
            send(SdbPacket.wrte, remote, packet.arg0, out.sublist(offset, (offset + chunk).clamp(0, out.length)));
          }
          send(SdbPacket.clse, remote, packet.arg0);
        } else if (service == 'sync:') {
          syncRemote = remote;
          syncLocal = packet.arg0;
          syncPath = null;
          received.clear();
        }
      } else if (packet.command == SdbPacket.wrte) {
        send(SdbPacket.okay, packet.arg1, packet.arg0);
        writeSizes.add(packet.data.length);
        final id = latin1.decode(packet.data.sublist(0, 4));
        final length = ByteData.sublistView(packet.data, 4, 8).getUint32(0, Endian.little);
        switch (id) {
          case 'SEND':
            final target = utf8.decode(packet.data.sublist(8, 8 + length));
            syncPath = target.substring(0, target.lastIndexOf(','));
            modes[syncPath] = int.parse(target.substring(target.lastIndexOf(',') + 1));
            if (failAtSend.contains(syncPath)) {
              final reason = utf8.encode('Permission denied');
              send(SdbPacket.wrte, syncRemote, syncLocal, [
                ...latin1.encode('FAIL'),
                ...(ByteData(4)..setUint32(0, reason.length, Endian.little)).buffer.asUint8List(),
                ...reason,
              ]);
            }
          case 'RECV':
            // The answer is one stream of frames, cut into packets with no regard for frame borders
            final stream = BytesBuilder();
            void frame(String name, List<int> body) {
              stream
                ..add(latin1.encode(name))
                ..add((ByteData(4)..setUint32(0, body.length, Endian.little)).buffer.asUint8List())
                ..add(body);
            }

            final content = files[utf8.decode(packet.data.sublist(8, 8 + length))];
            if (content == null) {
              frame('FAIL', utf8.encode('No such file or directory'));
            } else {
              for (var offset = 0; offset < content.length; offset += recvFrame) {
                frame('DATA', content.sublist(offset, (offset + recvFrame).clamp(0, content.length)));
              }
              frame('DONE', const []);
            }
            final all = stream.takeBytes();
            for (var offset = 0; offset < all.length; offset += recvChunk) {
              send(
                SdbPacket.wrte,
                syncRemote,
                syncLocal,
                all.sublist(offset, (offset + recvChunk).clamp(0, all.length)),
              );
            }
          case 'DATA':
            received.add(packet.data.sublist(8, 8 + length));
          case 'DONE':
            final path = syncPath!;
            if (refuseUploads.contains(path)) {
              final reason = utf8.encode('No space left on device');
              send(SdbPacket.wrte, syncRemote, syncLocal, [
                ...latin1.encode('FAIL'),
                ...(ByteData(4)..setUint32(0, reason.length, Endian.little)).buffer.asUint8List(),
                ...reason,
              ]);
            } else {
              files[path] = received.takeBytes();
              send(SdbPacket.wrte, syncRemote, syncLocal, latin1.encode('OKAY\u0000\u0000\u0000\u0000'));
            }
          case 'QUIT':
            send(SdbPacket.clse, syncRemote, syncLocal);
            if (staleClose) send(SdbPacket.clse, syncRemote, syncLocal);
        }
      }
    }
  }

  static const List<int> _sha1DigestInfo = [
    0x30,
    0x21,
    0x30,
    0x09,
    0x06,
    0x05,
    0x2b,
    0x0e,
    0x03,
    0x02,
    0x1a,
    0x05,
    0x00,
    0x04,
    0x14,
  ];

  /// RSA PKCS#1 v1.5 verification of the token under a SHA-1 DigestInfo, by plain arithmetic.
  static bool _verify((BigInt, BigInt) key, List<int> token, Uint8List signature) {
    final (n, e) = key;
    final k = (n.bitLength + 7) ~/ 8;
    if (signature.length != k) return false;
    var s = BigInt.zero;
    for (final byte in signature) {
      s = (s << 8) | BigInt.from(byte);
    }
    var m = s.modPow(e, n);
    final em = List<int>.filled(k, 0);
    for (var i = k - 1; i >= 0; i--) {
      em[i] = (m & BigInt.from(0xff)).toInt();
      m >>= 8;
    }
    final digestInfo = [..._sha1DigestInfo, ...token];
    final expected = [0, 1, ...List.filled(k - 3 - digestInfo.length, 0xff), 0, ...digestInfo];
    for (var i = 0; i < k; i++) {
      if (em[i] != expected[i]) return false;
    }
    return true;
  }

  /// Reads Android's RSAPublicKey struct without the client's help.
  static ((BigInt, BigInt), String) _parseKey(Uint8List data) {
    final text = ascii.decode(data).replaceAll('\u0000', '');
    final space = text.indexOf(' ');
    final struct = base64.decode(text.substring(0, space));
    final view = ByteData.sublistView(struct);
    if (view.getUint32(0, Endian.little) != 64) throw const FormatException('Not a 2048-bit key');
    var modulus = BigInt.zero;
    for (var i = 8 + 255; i >= 8; i--) {
      modulus = (modulus << 8) | BigInt.from(struct[i]);
    }
    final exponent = BigInt.from(view.getUint32(8 + 256 + 256, Endian.little));
    return ((modulus, exponent), text.substring(space + 1));
  }
}

/// Packets from a socket, one at a time; null once the connection has ended.
class _Reader {
  _Reader(Socket socket) {
    socket.listen(
      (data) {
        _pending = Uint8List.fromList([..._pending, ...data]);
        _wake();
      },
      onError: (Object _) => _end(),
      onDone: _end,
      cancelOnError: true,
    );
  }

  Uint8List _pending = Uint8List(0);
  bool _ended = false;
  Completer<void>? _waiter;
  final Completer<void> _closed = Completer();

  Future<SdbPacket?> next() async {
    while (true) {
      if (_pending.length >= SdbPacket.headerSize) {
        final header = ByteData.sublistView(_pending, 0, SdbPacket.headerSize);
        final length = header.getUint32(12, Endian.little);
        if (_pending.length >= SdbPacket.headerSize + length) {
          final packet = SdbPacket(
            header.getUint32(0, Endian.little),
            header.getUint32(4, Endian.little),
            header.getUint32(8, Endian.little),
            Uint8List.fromList(_pending.sublist(SdbPacket.headerSize, SdbPacket.headerSize + length)),
          );
          _pending = Uint8List.fromList(_pending.sublist(SdbPacket.headerSize + length));
          return packet;
        }
      }
      if (_ended) return null;
      await (_waiter = Completer()).future;
    }
  }

  Future<void> untilClosed() => _closed.future;

  void _end() {
    _ended = true;
    if (!_closed.isCompleted) _closed.complete();
    _wake();
  }

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }
}
