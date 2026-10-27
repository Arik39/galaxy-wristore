import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// A face to show in a [FaceDisc]: its picture when the phone has it, else a plain live dial stands in.
class DiscFace {
  const DiscFace({required this.id, required this.name, this.picture});

  final String id;
  final String name;
  final ImageProvider? picture;
}

/// A watch face shown the way the watch shows it: a round picture inside a hairline bezel with 60 ticks.
///
/// Swiping changes the face and turns the bezel with it, a tick under the finger for each face; screen readers turn it
/// with their adjust gestures. While the phone works with the watch, [progress] lights the ticks one by one from twelve
/// o'clock (-1 sends a short trail round for an unknown amount); each change of [turns] makes the bezel turn once all
/// the way round, the moment a job finishes. [dimmed] darkens the display, for a watch that is asleep or out of reach.
/// With Reduce Motion faces swap at once and the ring stands still between them.
class FaceDisc extends StatefulWidget {
  const FaceDisc({
    super.key,
    required this.faces,
    this.index = 0,
    this.onChanged,
    this.onTap,
    this.progress,
    this.turns = 0,
    this.dimmed = false,
    this.semanticHint,
  });

  final List<DiscFace> faces;
  final int index;
  final ValueChanged<int>? onChanged;
  final VoidCallback? onTap;
  final double? progress;
  final int turns;
  final bool dimmed;

  /// What tapping the disc does, for screen readers; the platform adds how to turn it.
  final String? semanticHint;

  @override
  State<FaceDisc> createState() => _FaceDiscState();
}

class _FaceDiscState extends State<FaceDisc> with TickerProviderStateMixin {
  late PageController _pages = PageController(initialPage: widget.index);
  late final AnimationController _spin = AnimationController(vsync: this, duration: Motion.medium);
  late final AnimationController _trail = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late int _index = widget.index;

  /// Each face is five minute ticks of the bezel.
  static const _step = 2 * math.pi / 12;

  bool get _still => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTrail();
  }

  @override
  void didUpdateWidget(FaceDisc old) {
    super.didUpdateWidget(old);
    if (widget.turns != old.turns && !_still) {
      _spin.forward(from: 0);
      HapticFeedback.mediumImpact();
    }
    if (widget.index != _index && widget.index < widget.faces.length && _pages.hasClients) {
      _index = widget.index;
      _pages.jumpToPage(widget.index);
    }
    if (widget.faces.length != old.faces.length && !_pages.hasClients) {
      _pages.dispose();
      _pages = PageController(initialPage: widget.index);
    }
    _syncTrail();
  }

  void _syncTrail() {
    final unknown = widget.progress != null && widget.progress! < 0;
    if (unknown && !_still) {
      if (!_trail.isAnimating) _trail.repeat();
    } else if (_trail.isAnimating) {
      _trail.stop();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _spin.dispose();
    _trail.dispose();
    super.dispose();
  }

  void _onPage(int i) {
    _index = i;
    HapticFeedback.selectionClick();
    widget.onChanged?.call(i);
  }

  /// Moves one face along, for screen readers' adjust gestures.
  void _move(int by) {
    final next = _index + by;
    if (next < 0 || next >= widget.faces.length || !_pages.hasClients) return;
    if (_still) {
      _pages.jumpToPage(next);
    } else {
      _pages.animateToPage(next, duration: Motion.short, curve: Motion.ease);
    }
  }

  @override
  Widget build(BuildContext context) {
    final faces = widget.faces;
    final current = faces.isEmpty ? null : faces[_index.clamp(0, faces.length - 1)];
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final disc = size * 0.86;
        final many = faces.length > 1;
        String place(int i) => '${faces[i].name}, ${i + 1} of ${faces.length}';
        return Semantics(
          label: 'Watch face',
          value: current == null ? null : place(_index),
          increasedValue: many && _index + 1 < faces.length ? place(_index + 1) : null,
          decreasedValue: many && _index > 0 ? place(_index - 1) : null,
          onIncrease: many && _index + 1 < faces.length ? () => _move(1) : null,
          onDecrease: many && _index > 0 ? () => _move(-1) : null,
          onTap: widget.onTap,
          hint: widget.semanticHint,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A faint pool of light beneath, so the disc sits on something.
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: size * 0.8,
                    height: size * 0.12,
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(colors: [Color(0x1FEDEFF2), Color(0x00EDEFF2)]),
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.all(Radius.elliptical(400, 60)),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: Listenable.merge([_pages, _spin, _trail]),
                  builder: (context, _) {
                    // With Reduce Motion the ring stands at the face shown rather than following the pages as they settle.
                    final page = !_still && _pages.hasClients && _pages.position.haveDimensions
                        ? (_pages.page ?? _index.toDouble())
                        : _index.toDouble();
                    final turn = Motion.ease.transform(_spin.value) * 2 * math.pi;
                    return CustomPaint(
                      size: Size.square(size),
                      painter: _Bezel(
                        angle: page * _step + turn,
                        progress: widget.progress,
                        trail: _trail.value,
                        still: _still,
                      ),
                    );
                  },
                ),
                SizedBox.square(
                  dimension: disc,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 18))],
                    ),
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onTap: widget.onTap,
                            child: faces.isEmpty
                                ? const _LiveDial()
                                : PageView.builder(
                                    controller: _pages,
                                    physics: _still ? const _SnapPages() : null,
                                    onPageChanged: _onPage,
                                    itemCount: faces.length,
                                    itemBuilder: (context, i) => faces[i].picture == null
                                        ? const _LiveDial()
                                        : Image(
                                            image: ResizeImage(
                                              faces[i].picture!,
                                              width: (disc * MediaQuery.devicePixelRatioOf(context)).round(),
                                            ),
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                            filterQuality: FilterQuality.high,
                                            errorBuilder: (context, _, _) => const _LiveDial(),
                                          ),
                                  ),
                          ),
                          // The glass over the display.
                          const IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment(0.2, 0.2),
                                  colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: widget.dimmed ? 0.62 : 0,
                              duration: Motion.medium,
                              child: const ColoredBox(color: Palette.void_),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Page physics that settle at once, for Reduce Motion: the face follows the finger, then snaps.
class _SnapPages extends PageScrollPhysics {
  const _SnapPages({super.parent});

  @override
  _SnapPages applyTo(ScrollPhysics? ancestor) => _SnapPages(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => const SpringDescription(mass: 1, stiffness: 20000, damping: 300);
}

/// The bezel: a hairline ring with 60 ticks, turned by [angle]; ticks light up as the progress.
class _Bezel extends CustomPainter {
  _Bezel({required this.angle, required this.progress, required this.trail, required this.still});

  final double angle;
  final double? progress;
  final double trail;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r * 0.995,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Palette.line,
    );
    canvas.drawCircle(
      c,
      r * 0.905,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Palette.lineFaint,
    );
    final value = progress;
    const full = 2 * math.pi;
    const tick = full / 60;
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      // Every tick turns with the bezel; progress lights the ticks that sit, right now, between twelve o'clock and
      // the progress, so it always reads from the top.
      final a = angle + tick * i;
      final onScreen = a % full;
      var on = false;
      if (value != null && value >= 0) {
        on = onScreen < value.clamp(0.0, 1.0) * full - tick / 2;
      } else if (value != null) {
        final behind = (trail * full - onScreen) % full;
        on = still ? major : behind < tick * 9;
      }
      final dir = Offset(math.sin(a), -math.cos(a));
      final inner = r * (major ? 0.925 : 0.945);
      final outer = r * 0.975;
      final alpha = on ? 1.0 : (major ? 0.62 : 0.26);
      canvas.drawLine(
        c + dir * inner,
        c + dir * outer,
        Paint()
          ..color = Palette.ink.withValues(alpha: alpha)
          ..strokeWidth = on ? 2.2 : (major ? 1.6 : 1)
          ..strokeCap = StrokeCap.round,
      );
    }
    // A notch at twelve that stays still: where the bezel's turn is read against.
    final top = c + Offset(0, -r * 0.995);
    canvas.drawPath(
      Path()
        ..moveTo(top.dx - 4, top.dy - 1)
        ..lineTo(top.dx + 4, top.dy - 1)
        ..lineTo(top.dx, top.dy + 5)
        ..close(),
      Paint()..color = Palette.ink,
    );
  }

  @override
  bool shouldRepaint(_Bezel old) =>
      old.angle != angle || old.progress != progress || old.trail != trail || old.still != still;
}

/// A plain dial showing the time, for a face whose picture the phone does not have yet.
class _LiveDial extends StatefulWidget {
  const _LiveDial();

  @override
  State<_LiveDial> createState() => _LiveDialState();
}

class _LiveDialState extends State<_LiveDial> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _DialPainter(DateTime.now()));
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.time);

  final DateTime time;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF1A1B1F), Color(0xFF0B0B0D)])
            .createShader(Offset.zero & size),
    );
    for (var i = 0; i < 12; i++) {
      final a = 2 * math.pi * i / 12;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        c + dir * r * 0.78,
        c + dir * r * 0.88,
        Paint()
          ..color = Palette.ink.withValues(alpha: i == 0 ? 1 : 0.7)
          ..strokeWidth = i % 3 == 0 ? 3 : 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
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

    hand((time.hour % 12 + time.minute / 60) / 12, r * 0.48, 4, Palette.ink);
    hand((time.minute + time.second / 60) / 60, r * 0.72, 2.6, Palette.ink);
    hand(time.second / 60, r * 0.78, 1, Palette.inkSoft);
    canvas.drawCircle(c, 3.5, Paint()..color = Palette.ink);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.time.second != time.second;
}
