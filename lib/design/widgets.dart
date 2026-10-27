import 'package:flutter/material.dart';

import 'icons.dart';
import 'tokens.dart';
import 'type.dart';

/// A small dot for a state; pulses while [pulse] is on.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, this.color = Palette.ink, this.pulse = false, this.size = 6});

  final Color color;
  final bool pulse;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _controller.repeat();
  }

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_controller.isAnimating) _controller.repeat();
    if (!widget.pulse && _controller.isAnimating) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: widget.size + 8,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = widget.pulse && !still ? _controller.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size + 7 * t + 4,
                height: widget.size + 7 * t + 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.14 * (1 - t)),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A figure over its tracked label: battery, counts, sizes. A long figure shrinks to fit rather than clip.
class Readout extends StatelessWidget {
  const Readout({super.key, required this.value, required this.label, this.risk = false});

  final String value;
  final String label;
  final bool risk;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: still ? Duration.zero : Motion.short,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Motion.ease)),
                  child: child,
                ),
              ),
              child: Text(
                value,
                key: ValueKey(value),
                style: AppType.figure.copyWith(color: risk ? Palette.alert : Palette.ink),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(), style: AppType.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Says plainly that the watch on screen is the demo one.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radii.control),
        border: Border.all(color: Palette.line),
      ),
      child: const Text('DEMO', style: AppType.label, maxLines: 1),
    );
  }
}

/// A section's label in tracked capitals over a hairline, with an optional action, or an info button, on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.onInfo, this.infoLabel});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onInfo;
  final String? infoLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.screen, Space.section, Space.screen - 8, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title.toUpperCase(), style: AppType.label.copyWith(color: Palette.inkSoft)),
                ),
              ),
              if (action != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: Palette.ink,
                    minimumSize: const Size(44, 36),
                    textStyle: AppType.button,
                  ),
                  child: Text(action!.toUpperCase()),
                ),
              if (onInfo != null)
                IconButton(
                  tooltip: infoLabel ?? 'About this',
                  onPressed: onInfo,
                  icon: const AppIconView(AppIcon.info, color: Palette.inkSoft, size: 20),
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
          // The row above reaches 8 further right, for its button's tap area; the hairline keeps to the margin.
          const Padding(padding: EdgeInsets.only(right: 8), child: Divider(height: 1)),
        ],
      ),
    );
  }
}

/// A line of a spec sheet: a tracked label on the left, its value on the right, a hairline under it. [risk] sets the
/// value in red, for what a reset would destroy.
class SpecRow extends StatelessWidget {
  const SpecRow(this.label, this.value, {super.key, this.risk = false});

  final String label;
  final String value;
  final bool risk;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Palette.line)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // The label takes the width it needs, up to half the row; the value has the rest, set flush right.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                child: Text(label.toUpperCase(), style: AppType.label, maxLines: 2),
              ),
              const SizedBox(width: Space.l),
              Expanded(
                child: Text(
                  value,
                  style: AppType.body.copyWith(color: risk ? Palette.alert : Palette.ink),
                  textAlign: TextAlign.end,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The red dot on what a reset would remove for good.
class RiskDot extends StatelessWidget {
  const RiskDot({super.key, this.size = 9});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Palette.alert,
        shape: BoxShape.circle,
        border: Border.all(color: Palette.void_, width: 2),
      ),
    );
  }
}

/// The bezel's 60 ticks laid in a line: they light up from the left as a job goes, or a short trail runs along them
/// while the amount is unknown. With Reduce Motion an unknown amount shows every fifth tick lit, still.
class TickBar extends StatefulWidget {
  const TickBar({super.key, required this.progress, this.height = 14});

  /// 0 to 1, or below 0 while the amount is unknown.
  final double progress;
  final double height;

  @override
  State<TickBar> createState() => _TickBarState();
}

class _TickBarState extends State<TickBar> with SingleTickerProviderStateMixin {
  late final _trail = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TickBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final moving = widget.progress < 0 && !MediaQuery.disableAnimationsOf(context);
    if (moving && !_trail.isAnimating) _trail.repeat();
    if (!moving && _trail.isAnimating) _trail.stop();
  }

  @override
  void dispose() {
    _trail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    return Semantics(
      label: 'Progress',
      value: p < 0 ? 'Working' : '${(p * 100).round()}%',
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _trail,
          builder: (context, _) => CustomPaint(
            painter: _TickLine(progress: p, trail: _trail.value, still: MediaQuery.disableAnimationsOf(context)),
          ),
        ),
      ),
    );
  }
}

class _TickLine extends CustomPainter {
  _TickLine({required this.progress, required this.trail, required this.still});

  final double progress;
  final double trail;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 60;
    final step = (size.width - 2) / (count - 1);
    for (var i = 0; i < count; i++) {
      final major = i % 5 == 0;
      final bool on;
      if (progress >= 0) {
        on = i < (progress.clamp(0.0, 1.0) * count).round();
      } else if (still) {
        on = major;
      } else {
        final head = trail * (count + 9);
        on = i <= head && i > head - 9;
      }
      final x = 1 + i * step;
      final top = major ? 0.0 : size.height * 0.4;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, size.height),
        Paint()
          ..color = Palette.ink.withValues(alpha: on ? 1 : (major ? 0.45 : 0.22))
          ..strokeWidth = on ? 2 : (major ? 1.4 : 1)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_TickLine old) => old.progress != progress || old.trail != trail || old.still != still;
}

/// What a running job is doing: its step in tracked capitals, its percentage, and the ticks lighting up. [ticks] is off
/// where a bezel on the same screen already shows the progress.
class JobProgress extends StatelessWidget {
  const JobProgress({super.key, required this.label, required this.progress, this.ticks = true});

  final String label;
  final double progress;
  final bool ticks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const StatusDot(pulse: true),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: AppType.label.copyWith(color: Palette.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (progress >= 0) Text('${(progress * 100).round()}%', style: AppType.figureSmall),
          ],
        ),
        if (ticks) ...[const SizedBox(height: Space.s), TickBar(progress: progress)],
      ],
    );
  }
}
