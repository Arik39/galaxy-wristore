import 'package:flutter/material.dart';

import 'tokens.dart';

/// Archivo, set wide and light, carries titles and figures; the platform's own face carries body text, so the app
/// reads native on iOS and Android. Labels are small tracked capitals. Every size follows the user's text size setting.
abstract final class AppType {
  static TextStyle _archivo(double size, double height, double weight, {double width = 125, double tracking = 0}) =>
      TextStyle(
        fontFamily: 'Archivo',
        fontSize: size,
        height: height / size,
        fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
        fontVariations: [FontVariation('wdth', width), FontVariation('wght', weight)],
        letterSpacing: tracking,
        color: Palette.ink,
      );

  /// The screen title, "My Watch".
  static final largeTitle = _archivo(26, 32, 300, tracking: 0.2);

  /// A section or sheet title.
  static final title = _archivo(20, 26, 380);

  /// A face's or app's name.
  static final name = _archivo(18, 23, 400);

  /// Figures: battery, counts, sizes. Tabular, so digits do not jump as they change.
  static final figure = _archivo(26, 30, 350, width: 112).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static final figureSmall = _archivo(
    17,
    22,
    400,
    width: 112,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Small tracked capitals for labels; pass the text in capitals. 11 is the smallest size iOS sets text at.
  static const label = TextStyle(
    fontSize: 11,
    height: 15 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.2,
    color: Palette.inkFaint,
  );

  static const body = TextStyle(fontSize: 16, height: 22 / 16, color: Palette.ink);
  static const bodyStrong = TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600, color: Palette.ink);
  static const secondary = TextStyle(fontSize: 14, height: 19 / 14, color: Palette.inkSoft);
  static const caption = TextStyle(fontSize: 13, height: 17 / 13, color: Palette.inkSoft);

  /// Button labels: tracked capitals.
  static const button = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w700, letterSpacing: 2.4);
}
