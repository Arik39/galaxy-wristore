import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'sdb_packet.dart';

/// Why a [PacketChannel] could not deliver a packet.
enum ChannelFailure {
  /// The connection was closed or reset, by either side.
  closed,

  /// Nothing arrived in time.
  timeout,

  /// What arrived is not sdb: a bad header or a packet larger than allowed.
  garbage,
}

/// Whether [error] says the other side reset the connection (ECONNRESET on Darwin, Linux and Windows). A busy sdb
/// daemon resets a second host's connection, sometimes before connecting has even finished.
bool isConnectionReset(Object error) => const {54, 104, 10054}.contains(switch (error) {
  SocketException(:final osError) => osError?.errorCode,
  // Connecting can report the reset as the operating system's error itself
  OSError(:final errorCode) => errorCode,
  _ => null,
});

class ChannelException implements Exception {
  const ChannelException(this.failure, this.message);

  final ChannelFailure failure;
  final String message;

  @override
  String toString() => 'ChannelException($failure): $message';
}

/// sdb packets over a socket. One reader at a time; packets larger than `maxData` are refused before they are
/// buffered whole, and reading from the socket pauses while unread packets pile up.
class PacketChannel {
  PacketChannel(this._socket, {required int maxData})
    : _maxData = maxData,
      _pauseAt = 2 * (SdbPacket.headerSize + maxData) {
    _subscription = _socket.listen(_onData, onError: _onError, onDone: _onDone, cancelOnError: true);
    // Write errors also surface here; reads report them already
    _socket.done.ignore();
  }

  final Socket _socket;
  final int _maxData;
  final int _pauseAt;
  late final StreamSubscription<Uint8List> _subscription;
  Uint8List _buffer = Uint8List(4096);
  int _length = 0;
  ChannelFailure? _ended;
  Completer<void>? _waiter;

  bool get isClosed => _ended != null;

  /// The next packet; [timeout] is how long to wait without receiving anything at all.
  Future<SdbPacket> read(Duration timeout) async {
    while (true) {
      final packet = _parse();
      if (packet != null) return packet;
      final ended = _ended;
      if (ended != null) throw ChannelException(ended, _describe(ended));
      final waiter = _waiter = Completer<void>();
      if (_subscription.isPaused) _subscription.resume();
      try {
        await waiter.future.timeout(timeout);
      } on TimeoutException {
        _waiter = null;
        throw ChannelException(ChannelFailure.timeout, _describe(ChannelFailure.timeout));
      }
    }
  }

  void send(SdbPacket packet) {
    final ended = _ended;
    if (ended != null) throw ChannelException(ended, _describe(ended));
    try {
      _socket.add(packet.encode());
    } catch (_) {
      _end(ChannelFailure.closed);
      throw const ChannelException(ChannelFailure.closed, 'The connection is closed');
    }
  }

  /// Closes the connection; a read waiting for a packet fails at once.
  void close() => _end(ChannelFailure.closed);

  SdbPacket? _parse() {
    if (_length < SdbPacket.headerSize) return null;
    final header = ByteData.sublistView(_buffer, 0, SdbPacket.headerSize);
    final command = header.getUint32(0, Endian.little);
    final length = header.getUint32(12, Endian.little);
    if (header.getUint32(20, Endian.little) != command ^ 0xffffffff || length > _maxData) {
      _end(ChannelFailure.garbage);
      throw ChannelException(ChannelFailure.garbage, _describe(ChannelFailure.garbage));
    }
    final total = SdbPacket.headerSize + length;
    if (_length < total) return null;
    final packet = SdbPacket(
      command,
      header.getUint32(4, Endian.little),
      header.getUint32(8, Endian.little),
      Uint8List.fromList(Uint8List.sublistView(_buffer, SdbPacket.headerSize, total)),
    );
    _buffer.setRange(0, _length - total, _buffer, total);
    _length -= total;
    return packet;
  }

  void _onData(Uint8List data) {
    if (_buffer.length - _length < data.length) {
      final grown = Uint8List(_length + data.length + (_length >> 1));
      grown.setRange(0, _length, _buffer);
      _buffer = grown;
    }
    _buffer.setRange(_length, _length + data.length, data);
    _length += data.length;
    if (_length >= _pauseAt) _subscription.pause();
    _wake();
  }

  void _onError(Object error, StackTrace stackTrace) => _end(ChannelFailure.closed);

  void _onDone() => _end(ChannelFailure.closed);

  void _end(ChannelFailure failure) {
    if (_ended == null) {
      _ended = failure;
      _socket.destroy();
      _subscription.cancel().ignore();
    }
    _wake();
  }

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  static String _describe(ChannelFailure failure) => switch (failure) {
    ChannelFailure.closed => 'The connection is closed',
    ChannelFailure.timeout => 'Nothing arrived in time',
    ChannelFailure.garbage => 'Not an sdb packet',
  };
}
