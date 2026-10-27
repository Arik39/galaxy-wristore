import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Near-black, one ink white, greys, and red for what is at risk. Nothing else carries colour: no glow, no neon.
abstract final class Palette {
  static const void_ = Color(0xFF09090A);
  static const graphite = Color(0xFF141518);
  static const graphiteHigh = Color(0xFF1C1D21);

  // Text, from loud to quiet.
  static const ink = Color(0xFFEDEFF2);
  static const inkSoft = Color(0xFFA8ADB5);
  static const inkFaint = Color(0xFF7A7F88);

  /// Live state and progress are drawn in ink: the world has no second accent.
  static const live = ink;

  /// What a reset would destroy, and refusals.
  static const alert = Color(0xFFE2554F);

  // Hairlines.
  static const line = Color(0x2EEDEFF2);
  static const lineFaint = Color(0x14EDEFF2);
}

/// One spacing rhythm for every screen.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;
  static const double screen = 22;
}

/// Precise, nearly square corners.
abstract final class Radii {
  static const control = Radius.circular(3);
  static const panel = Radius.circular(6);
}

/// Motion: exponential ease-out from an already visible state, always interruptible.
abstract final class Motion {
  static const short = Duration(milliseconds: 280);
  static const medium = Duration(milliseconds: 420);

  /// Exponential ease-out.
  static const ease = Cubic(0.16, 1, 0.3, 1);
}
