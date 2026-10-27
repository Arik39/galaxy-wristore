import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

/// A button in the world's language: a precise rectangle with a tracked capital label. [filled] is the one primary
/// action on a screen (white); the rest are outlined. [color] tints an outlined button, e.g. red for removing.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = true,
    this.color = Palette.ink,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(expand ? double.infinity : 44, 46)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.control))),
      textStyle: const WidgetStatePropertyAll(AppType.button),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (!filled) return Colors.transparent;
        if (states.contains(WidgetState.disabled)) return color.withValues(alpha: 0.18);
        if (states.contains(WidgetState.pressed)) return color.withValues(alpha: 0.85);
        return color;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        final base = filled ? Palette.void_ : color;
        if (states.contains(WidgetState.disabled)) return filled ? Palette.inkFaint : color.withValues(alpha: 0.4);
        return base;
      }),
      side: WidgetStateProperty.resolveWith(
        (states) => filled
            ? BorderSide.none
            : BorderSide(color: color.withValues(alpha: states.contains(WidgetState.disabled) ? 0.2 : 0.45)),
      ),
      overlayColor: WidgetStatePropertyAll((filled ? Palette.void_ : color).withValues(alpha: 0.08)),
    );
    // Two lines before an ellipsis, so a long label still reads at large text sizes.
    return TextButton(
      style: style,
      onPressed: onPressed,
      child: Text(label.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
    );
  }
}

/// The near-black backdrop behind every screen, with its faint dot grid.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: const _DotGrid(), child: child);
  }
}

class _DotGrid extends CustomPainter {
  const _DotGrid();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.void_);
    final dot = Paint()..color = const Color(0x0FFFFFFF);
    const step = 16.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGrid old) => false;
}
