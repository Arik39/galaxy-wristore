// Draws Galaxy Wristore's app icon in the app's own language: the bezel of 60 ticks with its notch at twelve, round a
// near-black display with two hands at 10:08. Run with `flutter test tool/app_icon_test.dart`; it writes
// assets/icon/app_icon.png (the full, opaque icon) and assets/icon/app_icon_foreground.png (the bezel alone on
// transparency, inside the safe zone of Android's adaptive icon).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/design/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('draw the app icon', () async {
    Directory('assets/icon').createSync(recursive: true);
    await _write('assets/icon/app_icon.png', await _draw(background: true, radius: 0.37));
    // Android masks the adaptive icon to its own shape; the safe zone is a circle of 66 of its 108 units.
    await _write('assets/icon/app_icon_foreground.png', await _draw(background: false, radius: 0.29));
  });
}

Future<ui.Image> _draw({required bool background, required double radius}) async {
  const size = 1024.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
  const c = Offset(size / 2, size / 2);
  final r = size * radius;
  if (background) canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = Palette.void_);

  // The display, a shade lighter than the ground, lit a little from above.
  canvas.drawCircle(
    c,
    r * 0.84,
    Paint()
      ..shader = ui.Gradient.radial(c.translate(0, -r * 0.3), r * 1.1, const [Color(0xFF1A1B1F), Color(0xFF0C0C0E)]),
  );
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.012
      ..color = Palette.ink.withValues(alpha: 0.32),
  );

  // The bezel's 60 ticks; every fifth longer and brighter.
  for (var i = 0; i < 60; i++) {
    final major = i % 5 == 0;
    final a = 2 * math.pi * i / 60;
    final dir = Offset(math.sin(a), -math.cos(a));
    canvas.drawLine(
      c + dir * r * (major ? 0.875 : 0.905),
      c + dir * r * 0.955,
      Paint()
        ..color = Palette.ink.withValues(alpha: major ? 0.9 : 0.38)
        ..strokeWidth = r * (major ? 0.022 : 0.011)
        ..strokeCap = StrokeCap.round,
    );
  }

  // The notch at twelve.
  final top = c + Offset(0, -r * 1.0);
  canvas.drawPath(
    Path()
      ..moveTo(top.dx - r * 0.05, top.dy - r * 0.035)
      ..lineTo(top.dx + r * 0.05, top.dy - r * 0.035)
      ..lineTo(top.dx, top.dy + r * 0.05)
      ..close(),
    Paint()..color = Palette.ink,
  );

  // Hands at 10:08, the time watches are photographed at.
  void hand(double turn, double length, double width) {
    final a = 2 * math.pi * turn;
    canvas.drawLine(
      c - Offset(math.sin(a), -math.cos(a)) * r * 0.08,
      c + Offset(math.sin(a), -math.cos(a)) * length,
      Paint()
        ..color = Palette.ink
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  hand((10 + 8 / 60) / 12, r * 0.42, r * 0.06);
  hand(8 / 60, r * 0.66, r * 0.04);
  canvas.drawCircle(c, r * 0.05, Paint()..color = Palette.ink);
  canvas.drawCircle(c, r * 0.02, Paint()..color = Palette.void_);

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  picture.dispose();
  return image;
}

Future<void> _write(String path, ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
}
