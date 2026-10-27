import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../api.dart';
import 'packet_channel.dart';
import 'sdb_packet.dart';

/// What a probe of one address found.
enum ProbeResult {
  /// Nothing answers on the sdb port.
  none,

  /// The port is open but whatever answers is not sdb.
  other,

  /// An sdb daemon: it answered the connection request with an authorization request or accepted it.
  sdb,

  /// An sdb daemon that closed the connection at once, as it does while another host is connected to it.
  sdbBusy,
}

/// Probes one host; [TcpSdbProbe] is the real one.
abstract interface class SdbProbe {
  Future<ProbeResult> probe(String host, Duration timeout);
}

/// Sends the sdb port a connection request and reads the first packet. The request makes the watch send an
/// authorization request and nothing more: no key is offered, so the watch shows no dialog.
class TcpSdbProbe implements SdbProbe {
  TcpSdbProbe({this.port = WatchAddress.sdbPort});

  final int port;

  /// A watch that has just woken needs at least this long to answer.
  static const Duration _minimumAnswerTime = Duration(seconds: 1);

  @override
  Future<ProbeResult> probe(String host, Duration timeout) async {
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } on Object catch (error) {
      return isConnectionReset(error) ? ProbeResult.sdbBusy : ProbeResult.none;
    }
    final channel = PacketChannel(socket, maxData: 1 << 16);
    try {
      channel.send(SdbPacket(SdbPacket.cnxn, 0x01000000, 0x40000, ascii.encode('host::\u0000')));
      final packet = await channel.read(timeout > _minimumAnswerTime ? timeout : _minimumAnswerTime);
      return packet.command == SdbPacket.auth || packet.command == SdbPacket.cnxn ? ProbeResult.sdb : ProbeResult.other;
    } on ChannelException catch (error) {
      return error.failure == ChannelFailure.closed ? ProbeResult.sdbBusy : ProbeResult.other;
    } finally {
      channel.close();
    }
  }
}

/// Looks for watches (sdb daemons) among addresses of the phone's own network.
class WatchScanner {
  WatchScanner({SdbProbe? probe, this.parallelism = 48}) : _probe = probe ?? TcpSdbProbe();

  final SdbProbe _probe;

  /// How many addresses are probed at a time.
  final int parallelism;

  static const Duration firstPassTimeout = Duration(milliseconds: 400);
  static const Duration secondPassTimeout = Duration(milliseconds: 1200);
  static const int _maxHosts = 1022;

  /// The watches among [candidates], in address order. A watch that sleeps wakes up on the first packet but answers too
  /// late for the short wait of the first pass, so when that finds nothing a second, patient pass follows.
  /// [onProgress] goes from 0 to 1.
  Future<List<FoundWatch>> scan(List<WatchAddress> candidates, {void Function(double fraction)? onProgress}) async {
    // The second pass waits three times as long, so the first gets a quarter of the bar
    var found = await _pass(candidates, firstPassTimeout, (done) => onProgress?.call(done * 0.25));
    if (found.isEmpty) {
      found = await _pass(candidates, secondPassTimeout, (done) => onProgress?.call(0.25 + done * 0.75));
    }
    onProgress?.call(1);
    return found..sort((a, b) => _value(a.address.host).compareTo(_value(b.address.host)));
  }

  Future<List<FoundWatch>> _pass(
    List<WatchAddress> candidates,
    Duration timeout,
    void Function(double) onProgress,
  ) async {
    final found = <FoundWatch>[];
    var next = 0;
    var done = 0;
    Future<void> worker() async {
      while (next < candidates.length) {
        final address = candidates[next++];
        switch (await _probe.probe(address.host, timeout)) {
          case ProbeResult.sdb:
            found.add(FoundWatch(address));
          case ProbeResult.sdbBusy:
            found.add(FoundWatch(address, busy: true));
          case ProbeResult.none || ProbeResult.other:
            break;
        }
        onProgress(++done / candidates.length);
      }
    }

    await Future.wait([for (var i = 0; i < min(max(parallelism, 1), candidates.length); i++) worker()]);
    return found;
  }

  /// The addresses to probe around [own], the phone's private IPv4 address in a network with [prefixLength]: the
  /// other hosts of its subnet. A network larger than about a thousand hosts is cut down to the /24 around the
  /// phone; an address that is not private, or a nonsense prefix, gives none.
  static List<WatchAddress> candidates(String own, int prefixLength) {
    final ownAddress = WatchAddress.parse(own);
    if (ownAddress == null || prefixLength < 1 || prefixLength > 30) return const [];
    final hosts = (1 << (32 - prefixLength)) - 2;
    final effective = hosts > _maxHosts ? 24 : prefixLength;
    final value = _value(ownAddress.host);
    final mask = (0xffffffff << (32 - effective)) & 0xffffffff;
    final network = value & mask;
    final broadcast = network | (~mask & 0xffffffff);
    return [
      for (var n = network + 1; n < broadcast; n++)
        if (n != value) ?WatchAddress.parse('${n >> 24 & 0xff}.${n >> 16 & 0xff}.${n >> 8 & 0xff}.${n & 0xff}'),
    ];
  }

  /// The prefix length of a dotted subnet [mask] such as `255.255.255.0`; null for anything that is not one.
  static int? prefixLengthOf(String mask) {
    final parts = mask.trim().split('.');
    if (parts.length != 4) return null;
    var value = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
      value = value << 8 | octet;
    }
    var length = 0;
    while (length < 32 && value & (0x80000000 >> length) != 0) {
      length++;
    }
    // The ones must be contiguous
    return value == (0xffffffff << (32 - length)) & 0xffffffff ? length : null;
  }

  static int _value(String host) => host.split('.').fold(0, (value, part) => value << 8 | int.parse(part));
}
