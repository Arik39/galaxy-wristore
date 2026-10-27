// Draws Galaxy Wristore's app icon: the words Wrist and Store in white under a small pale WATCH, on amber, set in
// Archivo, the app's own typeface. Run with `flutter test tool/app_icon_test.dart`, then tool/app_icons.sh, which
// makes every platform's icon files from what this writes to assets/icon. app_icon.png is the full square, opaque, for
// iOS. app_icon_rounded.png is a rounded square on transparency, for older Android, Windows and the README.
// app_icon_macos.png is inset and shadowed as macOS sets its icons. app_icon_foreground.png and
// app_icon_monochrome.png are the layers of Android's adaptive and themed icons, whose amber comes from
// res/drawable/ic_launcher_background.xml.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The icon's ground; ic_launcher_background.xml repeats it.
const amber = Color(0xFFF9B22C);

const _size = 1024.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('draw the app icon', () async {
    final font = File('assets/fonts/Archivo-Variable.ttf').readAsBytesSync();
    await (FontLoader('Archivo')..addFont(Future.value(ByteData.sublistView(font)))).load();
    Directory('assets/icon').createSync(recursive: true);
    await _writeOpaque('assets/icon/app_icon.png', _draw(ground: _Ground.square));
    await _write('assets/icon/app_icon_rounded.png', _draw(ground: _Ground.rounded, inset: 16));
    await _write('assets/icon/app_icon_macos.png', _draw(ground: _Ground.rounded, inset: 100, shadow: true));
    // Android shows the middle 72 of the adaptive icon's 108 units and may cut it to a circle, so the words are set a
    // little smaller there to stay inside the 66-unit safe zone.
    await _write('assets/icon/app_icon_foreground.png', _draw(ground: _Ground.none, scale: 0.6));
    await _write('assets/icon/app_icon_monochrome.png', _draw(ground: _Ground.none, scale: 0.6, monochrome: true));
  });
}

enum _Ground { none, square, rounded }

/// The icon on [ground]. A rounded ground sits [inset] inside the edges, and the words shrink with it; [scale] shrinks
/// the words alone. [monochrome] draws every word solid, as Android tints themed icons by their shape alone.
ui.Image _draw({
  required _Ground ground,
  double inset = 0,
  double scale = 1,
  bool shadow = false,
  bool monochrome = false,
}) {
  final recorder = ui.PictureRecorder();
  const bounds = Rect.fromLTWH(0, 0, _size, _size);
  final canvas = Canvas(recorder, bounds);
  final side = _size - 2 * inset;

  switch (ground) {
    case _Ground.none:
      break;
    case _Ground.square:
      canvas.drawRect(bounds, Paint()..color = amber);
    case _Ground.rounded:
      // The corner of a macOS icon: 185 of its 824 units.
      final shape = RRect.fromRectAndRadius(Rect.fromLTWH(inset, inset, side, side), Radius.circular(side * 0.225));
      if (shadow) {
        canvas.drawRRect(
          shape.shift(Offset(0, side * 0.012)),
          Paint()
            ..color = const Color(0x4D000000)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.012),
        );
      }
      canvas.drawRRect(shape, Paint()..color = amber);
  }

  final u = side * scale;
  const c = Offset(_size / 2, _size / 2);
  const white = Color(0xFFFFFFFF);
  _words(
    canvas,
    'WATCH',
    u * 0.075,
    700,
    monochrome ? white : const Color(0x9EFFFFFF),
    c.dy - u * 0.235,
    c.dx,
    spacing: u * 0.012,
  );
  _words(canvas, 'Wrist', u * 0.285, 640, white, c.dy + u * 0.035, c.dx);
  _words(canvas, 'Store', u * 0.285, 640, white, c.dy + u * 0.32, c.dx);

  final picture = recorder.endRecording();
  final image = picture.toImageSync(_size.toInt(), _size.toInt());
  picture.dispose();
  return image;
}

/// Sets [text] in Archivo at [weight], centred on [centre] with its baseline at [baseline].
void _words(
  Canvas canvas,
  String text,
  double size,
  double weight,
  Color color,
  double baseline,
  double centre, {
  double spacing = 0,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Archivo',
        fontSize: size,
        fontVariations: [FontVariation('wght', weight)],
        letterSpacing: spacing,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  // Letter spacing also follows the last letter; half of it on each side keeps the word centred.
  final top = baseline - painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  painter.paint(canvas, Offset(centre - painter.width / 2 + spacing / 2, top));
  painter.dispose();
}

Future<void> _write(String path, ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
}

/// Writes [image] as a PNG without an alpha channel, which the App Store asks of the iOS icon.
Future<void> _writeOpaque(String path, ui.Image image) async {
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final w = image.width, h = image.height;
  image.dispose();
  final rows = BytesBuilder();
  for (var y = 0; y < h; y++) {
    rows.addByte(0); // No filter.
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      rows.add([rgba[i], rgba[i + 1], rgba[i + 2]]);
    }
  }
  final header = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // 8 bits per channel
    ..setUint8(9, 2); // RGB
  File(path).writeAsBytesSync([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // The PNG signature.
    ..._chunk('IHDR', header.buffer.asUint8List()),
    ..._chunk('IDAT', zlib.encode(rows.takeBytes())),
    ..._chunk('IEND', const []),
  ]);
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  return [...length.buffer.asUint8List(), ...body, ...crc.buffer.asUint8List()];
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
