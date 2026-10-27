// Draws the picture GitHub shows when a link to the repository is shared: the icon, the name and two screens of the
// app, on the app's own near-black ground and dot grid. Run with `flutter test tool/social_preview_test.dart` after the
// icon or the screenshots change. It writes docs/social-preview.png, which is uploaded by hand on GitHub under
// Settings, Social preview.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/design/tokens.dart';

/// The size GitHub asks for; it shows the picture at 2:1.
const _width = 1280.0;
const _height = 640.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('draw the social preview', () async {
    final font = File('assets/fonts/Archivo-Variable.ttf').readAsBytesSync();
    await (FontLoader('Archivo')..addFont(Future.value(ByteData.sublistView(font)))).load();
    final icon = await _load('assets/icon/app_icon_rounded.png');
    final watch = await _load('docs/screenshots/watch.png');
    final discover = await _load('docs/screenshots/discover.png');

    final recorder = ui.PictureRecorder();
    const bounds = Rect.fromLTWH(0, 0, _width, _height);
    final canvas = Canvas(recorder, bounds);

    canvas.drawRect(bounds, Paint()..color = Palette.void_);
    final dot = Paint()..color = const Color(0x0FFFFFFF);
    const step = 24.0;
    for (var y = step / 2; y < _height; y += step) {
      for (var x = step / 2; x < _width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }

    canvas.drawImageRect(
      icon,
      _whole(icon),
      const Rect.fromLTWH(80, 84, 120, 120),
      Paint()..filterQuality = FilterQuality.high,
    );
    _text(canvas, 'Galaxy', left: 80, baseline: 306, size: 76, weight: 340, width: 125);
    _text(canvas, 'Wristore', left: 80, baseline: 390, size: 76, weight: 340, width: 125);
    _text(
      canvas,
      'Install, back up and restore the faces and apps on your Tizen watch.',
      left: 82,
      baseline: 456,
      size: 26,
      height: 1.4,
      color: Palette.inkSoft,
      maxWidth: 480,
    );
    _text(
      canvas,
      'ANDROID · IPHONE · WINDOWS · MAC · LINUX',
      left: 82,
      baseline: 566,
      size: 15,
      weight: 600,
      spacing: 2.8,
      color: Palette.inkFaint,
    );

    // Two screens of the demo watch, running off the bottom edge.
    _screen(canvas, watch, const Offset(660, 72));
    _screen(canvas, discover, const Offset(956, 132));

    final picture = recorder.endRecording();
    final image = picture.toImageSync(_width.toInt(), _height.toInt());
    picture.dispose();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/social-preview.png').writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
}

Future<ui.Image> _load(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Rect _whole(ui.Image image) => Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

/// Draws [screen] at [topLeft], rounded like a phone's display and edged with a hairline, since its ground is the
/// same near-black as the picture's.
void _screen(Canvas canvas, ui.Image screen, Offset topLeft) {
  const width = 268.0;
  final rect = topLeft & Size(width, width * screen.height / screen.width);
  final shape = RRect.fromRectAndRadius(rect, const Radius.circular(34));
  canvas
    ..save()
    ..clipRRect(shape)
    ..drawImageRect(screen, _whole(screen), rect, Paint()..filterQuality = FilterQuality.high)
    ..restore()
    ..drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Palette.line,
    );
}

/// Sets [text] in Archivo from [left], with its first baseline at [baseline], wrapping at [maxWidth].
void _text(
  Canvas canvas,
  String text, {
  required double left,
  required double baseline,
  required double size,
  double weight = 400,
  double width = 100,
  double spacing = 0,
  double height = 1.2,
  Color color = Palette.ink,
  double maxWidth = double.infinity,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Archivo',
        fontSize: size,
        height: height,
        fontVariations: [FontVariation('wdth', width), FontVariation('wght', weight)],
        letterSpacing: spacing,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, Offset(left, baseline - painter.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
  painter.dispose();
}
