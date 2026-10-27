import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../api.dart';
import '../util/text.dart';
import 'packet_channel.dart';
import 'sdb_key.dart';
import 'sdb_packet.dart';

/// How long an sdb connection waits; the defaults suit a watch whose Wi-Fi dozes.
class SdbOptions {
  const SdbOptions({
    this.connectTimeout = const Duration(seconds: 10),
    this.helloTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 120),
    this.approvalTimeout = const Duration(seconds: 60),
  });

  /// For the TCP connection.
  final Duration connectTimeout;

  /// For the first answer: a watch with Debugging off accepts the connection but never answers.
  final Duration helloTimeout;

  /// For every later answer, such as the output of a long installation.
  final Duration readTimeout;

  /// For the user to tap "Allow" on the watch after the key was offered.
  final Duration approvalTimeout;
}

/// Opens a TCP connection; [SdbSession.connect] uses `Socket.connect`, tests point it elsewhere.
typedef SocketConnector = Future<Socket> Function(String host, int port, Duration timeout);

/// What the installer needs from a connected watch; [SdbSession] is the real one. One call at a time.
abstract interface class SdbService {
  /// The watch's banner, for example `device::SM-R800::0`.
  String get banner;

  /// Runs [command] in the watch's shell and returns everything it printed; [onLine] sees complete lines as they
  /// arrive.
  Future<String> shell(String command, {void Function(String line)? onLine});

  /// Writes [data] to [remotePath], an absolute path of plain characters (letters, digits, `.`, `_`, `-`, `/`), with
  /// [mode]; [onProgress] gets the number of bytes sent so far.
  Future<void> push(
    String remotePath,
    Stream<List<int>> data, {
    int mode = SdbSession.defaultFileMode,
    void Function(int sent)? onProgress,
  });
}

/// An authorized sdb connection to one watch.
///
/// Calls run one after another, in the order they were made; [close] may be called at any time and makes a running
/// call fail at once. Failures are [WatchException]s.
class SdbSession implements SdbService {
  SdbSession._(this._channel, this.banner, this._maxData, this._options);

  final PacketChannel _channel;
  @override
  final String banner;
  final int _maxData;
  final SdbOptions _options;
  int _nextLocalId = 1;
  Future<void> _previous = Future.value();

  static const int defaultFileMode = 420;
  static const int _maxPacket = 1 << 20;
  static const int _maxChunk = 64 * 1024;
  static const int _syncHeader = 8;
  static const int _maxShellOutput = 4 << 20;
  static const int _maxFrame = 1 << 20;
  static const int _maxToken = 64;
  static const int _maxBanner = 256;

  /// sdbd announces 4 KiB or more; much less would leave no room for a file path or a command.
  static const int _minMaxData = 1024;
  static const int _hostVersion = 0x01000000;
  static const int _hostMaxData = 0x40000;
  static const int _authToken = 1;
  static const int _authSignature = 2;
  static const int _authPublicKey = 3;
  static final RegExp _pushPath = RegExp(r'^/[A-Za-z0-9._/-]{1,200}$');
  static const WatchException _busy = WatchException(
    WatchError.busy,
    'The watch closed the connection: another device may be connected to it',
  );

  /// Connects to [host] and authorizes with [key]. A key the watch has not seen makes it ask its user, and
  /// [onApprovalNeeded] is called when that happens; the wait is limited by [SdbOptions.approvalTimeout]. Completing
  /// [giveUp] during the handshake drops the connection, so the caller can open a new one and make the watch ask again.
  static Future<SdbSession> connect({
    required String host,
    required int port,
    required SdbKey key,
    required String keyName,
    SdbOptions options = const SdbOptions(),
    void Function()? onApprovalNeeded,
    Future<void>? giveUp,
    SocketConnector? connectSocket,
  }) async {
    final Socket socket;
    try {
      socket = await (connectSocket ?? _connectSocket)(host, port, options.connectTimeout);
    } on Object catch (error) {
      if (isConnectionReset(error)) throw _busy;
      throw WatchException(WatchError.unreachable, 'Cannot connect to the watch: $error');
    }
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } on Object {
      // Only a latency hint; a connection that is already gone shows at the first read
    }
    final channel = PacketChannel(socket, maxData: _maxPacket);
    var shaking = true;
    // Closing the channel makes the handshake's pending read fail at once, as a watch that dropped the connection.
    giveUp?.then((_) {
      if (shaking) channel.close();
    });
    try {
      final (banner, maxData) = await _handshake(channel, key, keyName, options, onApprovalNeeded);
      return SdbSession._(channel, banner, maxData, options);
    } catch (_) {
      channel.close();
      rethrow;
    } finally {
      shaking = false;
    }
  }

  static Future<Socket> _connectSocket(String host, int port, Duration timeout) =>
      Socket.connect(host, port, timeout: timeout);

  static Future<(String, int)> _handshake(
    PacketChannel channel,
    SdbKey key,
    String keyName,
    SdbOptions options,
    void Function()? onApprovalNeeded,
  ) async {
    try {
      channel.send(SdbPacket(SdbPacket.cnxn, _hostVersion, _hostMaxData, ascii.encode('host::\u0000')));
    } on ChannelException {
      throw _busy;
    }
    SdbPacket reply;
    try {
      reply = await channel.read(options.helloTimeout);
    } on ChannelException catch (error) {
      throw switch (error.failure) {
        ChannelFailure.closed => _busy,
        ChannelFailure.timeout => const WatchException(
          WatchError.notAnswering,
          'The watch does not answer: Debugging may be off, or the watch needs a restart',
        ),
        ChannelFailure.garbage => const WatchException(WatchError.protocol, 'Something answered that is not a watch'),
      };
    }
    var signed = false;
    var keySent = false;
    while (reply.command == SdbPacket.auth && reply.arg0 == _authToken) {
      try {
        if (!signed) {
          if (reply.data.isEmpty || reply.data.length > _maxToken) {
            throw const WatchException(WatchError.protocol, 'The watch sent an unexpected token');
          }
          channel.send(SdbPacket(SdbPacket.auth, _authSignature, 0, key.sign(reply.data)));
          signed = true;
        } else if (!keySent) {
          channel.send(SdbPacket(SdbPacket.auth, _authPublicKey, 0, key.adbPublicKey(keyName)));
          keySent = true;
          onApprovalNeeded?.call();
        } else {
          throw const WatchException(WatchError.approvalTimeout, 'The watch did not accept this phone');
        }
        reply = await channel.read(keySent ? options.approvalTimeout : options.readTimeout);
      } on ChannelException catch (error) {
        throw switch (error.failure) {
          ChannelFailure.closed when keySent => const WatchException(
            WatchError.approvalTimeout,
            'The watch did not allow this phone',
          ),
          ChannelFailure.timeout when keySent => const WatchException(
            WatchError.approvalTimeout,
            'Nobody allowed this phone on the watch in time',
          ),
          ChannelFailure.closed => const WatchException(WatchError.lost, 'The watch closed the connection'),
          ChannelFailure.timeout => const WatchException(WatchError.lost, 'The watch stopped answering'),
          ChannelFailure.garbage => const WatchException(
            WatchError.protocol,
            'The watch sent something that is not sdb',
          ),
        };
      }
    }
    if (reply.command != SdbPacket.cnxn) {
      throw const WatchException(WatchError.protocol, 'Unexpected answer from the watch');
    }
    if (reply.arg1 != 0 && reply.arg1 < _minMaxData) {
      throw const WatchException(WatchError.protocol, 'The watch announced packets too small to use');
    }
    final maxData = reply.arg1 > 0 ? min(reply.arg1, _hostMaxData) : 4096;
    final text = ascii.decode(reply.data, allowInvalid: true).replaceAll(RegExp(r'^[\x00-\x20]+|[\x00-\x20]+$'), '');
    return (takeRunes(String.fromCharCodes(text.runes.where((c) => !isIsoControl(c))), _maxBanner), maxData);
  }

  @override
  Future<String> shell(String command, {void Function(String line)? onLine}) => _exclusive(() async {
    final service = utf8.encode('shell:$command\u0000');
    if (command.contains('\u0000') || service.length > _maxData) {
      throw const WatchException(WatchError.refused, 'The command is too long or contains a NUL');
    }
    final stream = await _open(service);
    final all = BytesBuilder(copy: false);
    final lines = _Lines(onLine);
    while (true) {
      final packet = await _next(stream.local);
      if (packet.command == SdbPacket.wrte) {
        all.add(packet.data);
        if (all.length > _maxShellOutput) {
          _send(SdbPacket.clse, stream.local, stream.remote);
          throw const WatchException(WatchError.protocol, 'The command printed too much');
        }
        _send(SdbPacket.okay, stream.local, stream.remote);
        lines.add(packet.data);
      } else if (packet.command == SdbPacket.clse) {
        _send(SdbPacket.clse, stream.local, stream.remote);
        break;
      }
    }
    lines.close();
    return utf8.decode(all.takeBytes(), allowMalformed: true);
  });

  @override
  Future<void> push(
    String remotePath,
    Stream<List<int>> data, {
    int mode = defaultFileMode,
    void Function(int sent)? onProgress,
  }) {
    if (!_pushPath.hasMatch(remotePath)) {
      return Future.error(const WatchException(WatchError.refused, 'Unsupported remote path'));
    }
    return _sendFile(remotePath, data, mode, onProgress);
  }

  /// Like [push], for any absolute path without control characters, commas or `..` parts (a media file's name may have
  /// spaces). Nothing runs in a shell here, and such a path must not be put into a shell command afterwards.
  Future<void> upload(
    String remotePath,
    Stream<List<int>> data, {
    int mode = defaultFileMode,
    void Function(int sent)? onProgress,
  }) {
    // A send request ends the path at its last comma, where the mode begins
    if (!isFilePath(remotePath) || remotePath.contains(',')) {
      return Future.error(const WatchException(WatchError.refused, 'Unsupported remote path'));
    }
    return _sendFile(remotePath, data, mode, onProgress);
  }

  /// Reads the file at [remotePath] (an absolute path without control characters or `..` parts), handing its bytes
  /// to [onData] as they arrive; returns its size. More than [maxBytes] ends the transfer with
  /// [WatchError.refused]. The watch answers with frames (data, then done, or a failure) that its packets may cut
  /// anywhere.
  Future<int> pull(
    String remotePath,
    void Function(Uint8List bytes) onData, {
    int? maxBytes,
    void Function(int received)? onProgress,
  }) {
    if (!isFilePath(remotePath)) {
      return Future.error(const WatchException(WatchError.refused, 'Unsupported remote path'));
    }
    return _exclusive(() async {
      final stream = await _open(utf8.encode('sync:\u0000'));
      final path = utf8.encode(remotePath);
      _send(SdbPacket.wrte, stream.local, stream.remote, _syncCommand('RECV', path.length, path));
      var pending = Uint8List(0);
      var received = 0;
      while (true) {
        final packet = await _next(stream.local);
        switch (packet.command) {
          case SdbPacket.okay:
            continue;
          case SdbPacket.wrte:
            _send(SdbPacket.okay, stream.local, stream.remote);
          case SdbPacket.clse:
            throw const WatchException(WatchError.lost, 'The watch ended the transfer');
          default:
            throw const WatchException(WatchError.protocol, 'Unexpected answer during a transfer');
        }
        pending =
            (BytesBuilder(copy: false)
                  ..add(pending)
                  ..add(packet.data))
                .takeBytes();
        var offset = 0;
        while (pending.length - offset >= _syncHeader) {
          final frame = ascii.decode(pending.sublist(offset, offset + 4), allowInvalid: true);
          final length = ByteData.sublistView(pending, offset + 4, offset + 8).getInt32(0, Endian.little);
          if (frame == 'DONE') {
            _sendSync(stream, 'QUIT');
            return received;
          }
          if (frame != 'DATA' && frame != 'FAIL') {
            throw const WatchException(WatchError.protocol, 'Unexpected transfer frame');
          }
          if (length < 0 || length > _maxFrame) throw const WatchException(WatchError.protocol, 'Bad transfer frame');
          if (pending.length - offset - _syncHeader < length) break;
          final body = Uint8List.fromList(pending.sublist(offset + _syncHeader, offset + _syncHeader + length));
          if (frame == 'FAIL') {
            _sendSync(stream, 'QUIT');
            throw WatchException(WatchError.refused, 'The watch could not send the file: ${_text(body)}');
          }
          received += length;
          if (maxBytes != null && received > maxBytes) {
            _send(SdbPacket.clse, stream.local, stream.remote);
            throw WatchException(WatchError.refused, 'The file is larger than $maxBytes bytes');
          }
          onData(body);
          onProgress?.call(received);
          offset += _syncHeader + length;
        }
        pending = pending.sublist(offset);
      }
    });
  }

  /// Ends the connection; a call that is running fails with [WatchError.lost].
  Future<void> close() async => _channel.close();

  /// An absolute path of a file: no control characters, no `..` part, a sane length.
  static bool isFilePath(String path) =>
      path.length >= 2 &&
      path.length <= 1024 &&
      path.startsWith('/') &&
      !path.endsWith('/') &&
      !hasIsoControl(path) &&
      !path.split('/').contains('..');

  Future<void> _sendFile(String remotePath, Stream<List<int>> data, int mode, void Function(int sent)? onProgress) =>
      _exclusive(() async {
        final stream = await _open(utf8.encode('sync:\u0000'));
        try {
          final target = utf8.encode('$remotePath,$mode');
          await _writeSync(stream, 'SEND', target.length, target);
          final chunkSize = min(_maxChunk, _maxData - _syncHeader);
          var sent = 0;
          await for (final chunk in data) {
            for (var offset = 0; offset < chunk.length; offset += chunkSize) {
              final piece = chunk.sublist(offset, min(offset + chunkSize, chunk.length));
              await _writeSync(stream, 'DATA', piece.length, piece);
              sent += piece.length;
              onProgress?.call(sent);
            }
          }
          await _writeSync(stream, 'DONE', DateTime.now().millisecondsSinceEpoch ~/ 1000, const []);
          final reply = await _next(stream.local);
          if (reply.command != SdbPacket.wrte) {
            throw const WatchException(WatchError.protocol, 'No answer to the file transfer');
          }
          _send(SdbPacket.okay, stream.local, stream.remote);
          if (!_startsWith(reply.data, 'OKAY')) {
            throw WatchException(WatchError.refused, 'The watch refused the file: ${_failReason(reply.data)}');
          }
          // The service closes itself; whatever it still sends is skipped by its local id in the next call
          _sendSync(stream, 'QUIT');
        } on ChannelException {
          rethrow;
        } catch (_) {
          // The data could not be read or the watch refused it: the transfer is closed without its end, so the watch
          // drops the partial file
          _abandon(stream);
          rethrow;
        }
      });

  /// Runs [action] after every call made before it has ended, translating a broken connection.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _previous;
    final done = Completer<void>();
    _previous = done.future;
    return previous.then((_) async {
      try {
        if (_channel.isClosed) throw const WatchException(WatchError.lost, 'The connection to the watch is closed');
        return await action();
      } on ChannelException catch (error) {
        throw switch (error.failure) {
          ChannelFailure.closed => const WatchException(WatchError.lost, 'The connection to the watch broke'),
          ChannelFailure.timeout => const WatchException(WatchError.lost, 'The watch stopped answering'),
          ChannelFailure.garbage => const WatchException(
            WatchError.protocol,
            'The watch sent something that is not sdb',
          ),
        };
      } finally {
        done.complete();
      }
    });
  }

  Future<_Stream> _open(List<int> service) async {
    final local = _nextLocalId++;
    _send(SdbPacket.open, local, 0, service);
    final packet = await _next(local);
    if (packet.command != SdbPacket.okay) {
      throw const WatchException(WatchError.refused, 'The watch refused the service');
    }
    return _Stream(local, packet.arg0);
  }

  /// The next packet addressed to [local]; packets of earlier, already finished services are dropped.
  Future<SdbPacket> _next(int local) async {
    while (true) {
      final packet = await _channel.read(_options.readTimeout);
      if (packet.arg1 == local) return packet;
    }
  }

  void _send(int command, int arg0, int arg1, [List<int> data = const []]) =>
      _channel.send(SdbPacket(command, arg0, arg1, Uint8List.fromList(data)));

  /// Sends a sync request and waits for the watch to take it. A watch that cannot write the file (no permission, no
  /// space) answers with a failure instead, and that is a refusal with its reason.
  Future<void> _writeSync(_Stream stream, String id, int length, List<int> payload) async {
    _send(SdbPacket.wrte, stream.local, stream.remote, _syncCommand(id, length, payload));
    final answer = await _next(stream.local);
    if (answer.command == SdbPacket.okay) return;
    if (answer.command == SdbPacket.wrte && _startsWith(answer.data, 'FAIL')) {
      _send(SdbPacket.okay, stream.local, stream.remote);
      throw WatchException(WatchError.refused, 'The watch refused the file: ${_failReason(answer.data)}');
    }
    throw const WatchException(WatchError.protocol, 'The write was not acknowledged');
  }

  void _sendSync(_Stream stream, String id) =>
      _send(SdbPacket.wrte, stream.local, stream.remote, _syncCommand(id, 0, const []));

  void _abandon(_Stream stream) {
    try {
      _send(SdbPacket.clse, stream.local, stream.remote);
    } on ChannelException {
      // Already gone
    }
  }

  static Uint8List _syncCommand(String id, int length, List<int> payload) {
    final bytes = Uint8List(_syncHeader + payload.length);
    bytes.setRange(0, 4, ascii.encode(id));
    ByteData.sublistView(bytes).setUint32(4, length & 0xffffffff, Endian.little);
    bytes.setRange(_syncHeader, bytes.length, payload);
    return bytes;
  }

  static bool _startsWith(Uint8List data, String id) =>
      data.length >= 4 && ascii.decode(data.sublist(0, 4), allowInvalid: true) == id;

  /// The reason in a failure frame (`FAIL`, its length, the text).
  static String _failReason(Uint8List frame) {
    if (frame.length <= _syncHeader) return 'no reason given';
    final length = ByteData.sublistView(frame, 4, 8).getUint32(0, Endian.little);
    return _text(frame.sublist(_syncHeader, min(frame.length, _syncHeader + length)));
  }

  /// The watch's words for a failure: one line of plain text.
  static String _text(List<int> bytes) =>
      cleanLine(utf8.decode(bytes.take(1000).toList(), allowMalformed: true), 300) ?? 'no reason given';
}

class _Stream {
  _Stream(this.local, this.remote);

  final int local;
  final int remote;
}

/// Cuts shell output into lines as it arrives; a line ends at a newline, a carriage return before it is dropped.
class _Lines {
  _Lines(this._onLine);

  final void Function(String line)? _onLine;
  final BytesBuilder _pending = BytesBuilder();

  void add(Uint8List data) {
    if (_onLine == null) return;
    var start = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i] == 0x0a) {
        _pending.add(Uint8List.sublistView(data, start, i));
        _emit(_pending.takeBytes());
        start = i + 1;
      }
    }
    _pending.add(Uint8List.sublistView(data, start));
  }

  void close() {
    if (_onLine != null && _pending.isNotEmpty) _emit(_pending.takeBytes());
  }

  void _emit(Uint8List bytes) {
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0x0d) {
      end--;
    }
    _onLine!(utf8.decode(Uint8List.sublistView(bytes, 0, end), allowMalformed: true));
  }
}
