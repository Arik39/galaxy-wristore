import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/type.dart';

/// A face's or app's picture: the real one when the phone has it, otherwise its initials on graphite. Faces are round,
/// as on the watch. [ring] draws a hairline around it with a small gap; [bezel] draws the watch's 60 ticks instead, for
/// the face on the wrist.
class PackagePicture extends StatelessWidget {
  const PackagePicture({
    super.key,
    required this.name,
    this.file,
    this.bytes,
    this.round = true,
    this.size = 88,
    this.ring,
    this.bezel = false,
  });

  final String name;
  final File? file;
  final Uint8List? bytes;
  final bool round;
  final double size;
  final Color? ring;
  final bool bezel;

  @override
  Widget build(BuildContext context) {
    final inner = bezel ? size - 16 : (ring == null ? size : size - 10);
    final radius = BorderRadius.circular(round ? inner / 2 : inner * 0.24);
    final Widget picture;
    if (file != null || bytes != null) {
      final provider = file != null ? FileImage(file!) as ImageProvider : MemoryImage(bytes!);
      picture = Image(
        image: ResizeImage(provider, width: (inner * MediaQuery.devicePixelRatioOf(context)).round()),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, _) => _initials(inner, radius),
      );
    } else {
      picture = _initials(inner, radius);
    }
    final clipped = SizedBox.square(
      dimension: inner,
      child: ClipRRect(borderRadius: radius, child: picture),
    );
    if (bezel) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(
          foregroundPainter: const _Ticks(),
          child: Center(child: clipped),
        ),
      );
    }
    if (ring == null) return clipped;
    return AnimatedContainer(
      duration: Motion.short,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(round ? size / 2 : size * 0.24),
        border: Border.all(color: ring!),
      ),
      child: clipped,
    );
  }

  Widget _initials(double inner, BorderRadius radius) {
    final words = name.split(RegExp(r'[\s_]+')).where((w) => w.isNotEmpty).toList();
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.graphite,
        borderRadius: radius,
        border: Border.all(color: Palette.lineFaint),
      ),
      child: Center(
        child: Text(
          letters,
          style: AppType.name.copyWith(fontSize: inner * 0.22, color: Palette.inkSoft),
        ),
      ),
    );
  }
}

/// A bezel's 60 ticks round a picture, every fifth longer.
class _Ticks extends CustomPainter {
  const _Ticks();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      final a = 2 * math.pi * i / 60;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        c + dir * (r - (major ? 6.5 : 4.5)),
        c + dir * (r - 1),
        Paint()
          ..color = Palette.ink.withValues(alpha: major ? 1 : 0.55)
          ..strokeWidth = major ? 1.6 : 1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_Ticks old) => false;
}

/// A grid of pictures with lines of text under each. A tile is as tall as its picture plus [lines] at the user's text
/// size, so names never clip, however large the text is set.
class PictureGrid extends StatelessWidget {
  const PictureGrid({
    super.key,
    required this.maxTile,
    required this.lines,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = Space.m,
  });

  /// The widest a tile may be; the grid uses as many columns as that allows, at least two.
  final double maxTile;

  /// The text under a picture, one style per line.
  final List<TextStyle> lines;

  /// The space between the picture and its text.
  final double gap;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final text = lines.fold(0.0, (sum, s) => sum + (s.height ?? 1.2) * scaler.scale(s.fontSize ?? 14));
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const across = Space.xl;
        final width = constraints.crossAxisExtent;
        final columns = math.max(2, (width / maxTile).ceil());
        final tile = (width - across * (columns - 1)) / columns;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: across,
            mainAxisSpacing: Space.xl,
            mainAxisExtent: tile + gap + text + 2,
          ),
          delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemCount),
        );
      },
    );
  }
}
