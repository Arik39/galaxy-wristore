import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Pictures for the demo watch: a preview for each demo face and a round icon for each demo app, drawn here so the
/// demo shows the app as it looks with a real watch. Faces are set at 10:08, the time watches are photographed at.
Future<Uint8List> demoPicture(String packageId, {required bool face}) async {
  const size = 360.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
  if (face) {
    _face(canvas, size, _styles[packageId] ?? _styles.values.elementAt(packageId.hashCode.abs() % _styles.length));
  } else {
    _appIcon(canvas, size, packageId);
  }
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _Style {
  const _Style(
    this.dial,
    this.index,
    this.accent, {
    this.ring,
    this.numerals = false,
    this.sunburst = false,
    this.digital = false,
    this.subdials = false,
    this.lume = false,
  });

  final List<Color> dial;
  final Color index;
  final Color accent;
  final Color? ring;
  final bool numerals, sunburst, digital, subdials, lume;
}

const _styles = <String, _Style>{
  'com.watchface.GSHybrid7': _Style(
    [Color(0xFF2B2F38), Color(0xFF0B0C0F)],
    Color(0xFFF2F2F2),
    Color(0xFFE8443A),
    digital: true,
    subdials: true,
  ),
  'com.watchface.GSHybrid6': _Style(
    [Color(0xFF1E3A5F), Color(0xFF0A1424)],
    Color(0xFFE6EEF7),
    Color(0xFFF5B85C),
    digital: true,
    subdials: true,
  ),
  'com.watchface.1224ComboWatch': _Style(
    [Color(0xFF262626), Color(0xFF050505)],
    Color(0xFFDDDDDD),
    Color(0xFF7DE3F5),
    numerals: true,
    ring: Color(0xFF3A3A3A),
  ),
  'com.watchface.Active': _Style(
    [Color(0xFF151515), Color(0xFF000000)],
    Color(0xFFFFFFFF),
    Color(0xFFF2C230),
    ring: Color(0xFFF2C230),
    digital: true,
  ),
  'com.watchface.BalloziSKYNOX': _Style(
    [Color(0xFF3B6FD8), Color(0xFF0E1E4A)],
    Color(0xFFE4E8F0),
    Color(0xFFFF8A3D),
    sunburst: true,
    subdials: true,
  ),
  'com.watchface.MD210': _Style(
    [Color(0xFF3A3A3A), Color(0xFF121212)],
    Color(0xFFF2F2F2),
    Color(0xFF46D27A),
    sunburst: true,
    digital: true,
  ),
  'com.watchface.MessaRT18': _Style(
    [Color(0xFF6B1219), Color(0xFF1A0204)],
    Color(0xFFD9B26A),
    Color(0xFFD9B26A),
    numerals: true,
  ),
  'ru.zakharova.OceanWatchII': _Style(
    [Color(0xFF0B4F6C), Color(0xFF03141E)],
    Color(0xFFB8F5D0),
    Color(0xFFFF7A00),
    lume: true,
    ring: Color(0xFF0E2A3A),
  ),
  'com.watchface.RolmaArmy': _Style(
    [Color(0xFF55613E), Color(0xFF1B2013)],
    Color(0xFFEDE3C8),
    Color(0xFFE0B04C),
    numerals: true,
  ),
};

void _face(Canvas canvas, double size, _Style s) {
  final c = Offset(size / 2, size / 2);
  final r = size / 2;
  canvas.drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = const Color(0xFF000000));
  canvas.drawCircle(c, r, Paint()..shader = ui.Gradient.radial(c.translate(0, -r * 0.3), r * 1.15, s.dial));
  if (s.sunburst) {
    final ray = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 180; i++) {
      final a = 2 * math.pi * i / 180;
      canvas.drawLine(c, c + Offset(math.sin(a), -math.cos(a)) * r, ray);
    }
  }
  if (s.ring != null) {
    canvas.drawCircle(
      c,
      r * 0.93,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = s.ring!,
    );
  }
  // Minute track and hour marks.
  for (var i = 0; i < 60; i++) {
    final a = 2 * math.pi * i / 60;
    final dir = Offset(math.sin(a), -math.cos(a));
    final hour = i % 5 == 0;
    final paint = Paint()
      ..color = hour ? s.index : s.index.withValues(alpha: 0.45)
      ..strokeWidth = hour ? 7 : 2
      ..strokeCap = StrokeCap.round;
    if (hour && s.lume) {
      canvas.drawCircle(c + dir * (r * 0.74), 9, Paint()..color = s.index);
    } else if (!(hour && s.numerals)) {
      canvas.drawLine(c + dir * (r * (hour ? 0.70 : 0.78)), c + dir * (r * 0.84), paint);
    }
  }
  if (s.numerals) {
    for (final (n, a) in [(12, 0.0), (3, 0.5), (6, 1.0), (9, 1.5)]) {
      final dir = Offset(math.sin(math.pi * a), -math.cos(math.pi * a));
      _text(canvas, '$n', c + dir * (r * 0.70), 40, s.index, 700);
    }
  }
  if (s.subdials) {
    for (final dx in [-0.36, 0.36]) {
      final sc = c + Offset(r * dx, r * 0.18);
      canvas.drawCircle(
        sc,
        r * 0.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = s.index.withValues(alpha: 0.6),
      );
      canvas.drawLine(
        sc,
        sc + Offset(r * 0.12, -r * 0.06),
        Paint()
          ..color = s.accent
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }
  if (s.digital) _text(canvas, '10:08', c.translate(0, -r * 0.33), 42, s.index, 600);
  // Hands at 10:08.
  void hand(double turn, double length, double width, Color color) {
    final a = 2 * math.pi * turn;
    canvas.drawLine(
      c,
      c + Offset(math.sin(a), -math.cos(a)) * length,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  hand((10 + 8 / 60) / 12, r * 0.45, 12, s.index);
  hand(8 / 60, r * 0.70, 8, s.index);
  hand(0.62, r * 0.78, 3, s.accent);
  canvas.drawCircle(c, 10, Paint()..color = s.accent);
}

void _appIcon(Canvas canvas, double size, String id) {
  const colors = [
    [Color(0xFFF2C230), Color(0xFFE08A14)],
    [Color(0xFF5AA9FF), Color(0xFF2F5BD8)],
    [Color(0xFFFF7A59), Color(0xFFD9333F)],
    [Color(0xFF7BD88F), Color(0xFF239B56)],
    [Color(0xFFB08CFF), Color(0xFF6C4AB6)],
    [Color(0xFF6BE3D6), Color(0xFF1B8C8C)],
  ];
  final pair = colors[id.hashCode.abs() % colors.length];
  final c = Offset(size / 2, size / 2);
  canvas.drawCircle(c, size / 2, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(size, size), pair));
  final name = id.split('.').last.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  _text(
    canvas,
    name.isEmpty ? '?' : name.substring(0, math.min(2, name.length)).toUpperCase(),
    c,
    120,
    const Color(0xFFFFFFFF),
    700,
  );
}

void _text(Canvas canvas, String text, Offset centre, double size, Color color, double weight) {
  final builder =
      ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontFamily: 'Archivo', fontSize: size))
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontFamily: 'Archivo',
            fontSize: size,
            fontVariations: [ui.FontVariation('wght', weight)],
          ),
        )
        ..addText(text);
  final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 360));
  canvas.drawParagraph(paragraph, centre.translate(-180, -paragraph.height / 2));
}
