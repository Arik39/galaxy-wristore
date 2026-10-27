import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'controls.dart';
import 'icons.dart';
import 'tokens.dart';
import 'type.dart';

/// A page with its title in Archivo, wide and light. A section's own page keeps the title where My Watch has it, top
/// left with its actions on the right, and the bar turns solid with a hairline once content scrolls under it. A page
/// pushed over another has a back chevron and a title that hands over to a small centred one as it scrolls; it paints
/// its own backdrop, so the page beneath does not show through while it slides in. [bottom] stays pinned under the
/// content, above the tab bar. On a tablet the content keeps a readable width, centred.
class TabPage extends StatelessWidget {
  const TabPage({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.onRefresh,
    this.bottom,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final Widget? bottom;

  /// The widest the content runs; beyond it, it is centred.
  static const maxContentWidth = 720.0;

  /// The space either side of the content on a screen wider than [maxContentWidth].
  static double sideOf(BuildContext context) => math.max(0, (MediaQuery.sizeOf(context).width - maxContentWidth) / 2);

  /// How far titles follow the user's text size: all the way to half as large again, then they hold, as the platforms'
  /// own large titles do.
  static const maxTitleScale = 1.5;

  /// The height of a section's title row, which grows with the user's text size: My Watch's header uses it too.
  static double titleRowOf(BuildContext context) => 24 + 32 * _titleScale(context);

  static double _titleScale(BuildContext context) =>
      math.min(MediaQuery.textScalerOf(context).scale(26) / 26, maxTitleScale).toDouble();

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final inset = MediaQuery.paddingOf(context);
    final side = sideOf(context);
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _Title(
            title: title,
            actions: actions,
            topInset: inset.top,
            canPop: canPop,
            side: side,
            titleScale: _titleScale(context),
          ),
        ),
        if (side == 0)
          ...slivers
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side),
            sliver: SliverMainAxisGroup(slivers: slivers),
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottom == null ? inset.bottom + Space.section : Space.l)),
      ],
    );
    Widget page = onRefresh == null
        ? scroll
        : RefreshIndicator.adaptive(
            onRefresh: onRefresh!,
            color: Palette.ink,
            edgeOffset: inset.top + (canPop ? _Title.bar : titleRowOf(context)),
            child: scroll,
          );
    if (bottom != null) {
      page = Column(
        children: [
          Expanded(child: page),
          bottom!,
        ],
      );
    }
    // Ink of rows and buttons paints on this page, above its backdrop.
    page = Material(type: MaterialType.transparency, child: page);
    return canPop ? Backdrop(child: page) : page;
  }
}

class _Title extends SliverPersistentHeaderDelegate {
  _Title({
    required this.title,
    required this.actions,
    required this.topInset,
    required this.canPop,
    required this.side,
    required this.titleScale,
  });

  final String title;
  final List<Widget> actions;
  final double topInset;
  final bool canPop;
  final double side;
  final double titleScale;

  /// The row with the back chevron and the small title.
  static const bar = 52.0;

  /// The large title's own band under the bar, and a section's title row (the same place and size as My Watch's):
  /// both grow with the text size.
  double get _large => 18 + 32 * titleScale;
  double get _root => 24 + 32 * titleScale;

  @override
  double get minExtent => topInset + (canPop ? bar : _root);

  @override
  double get maxExtent => topInset + (canPop ? bar + _large : _root);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    if (!canPop) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: overlapsContent ? 1 : 0,
            duration: Motion.short,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xF209090A),
                border: Border(bottom: BorderSide(color: Palette.lineFaint)),
              ),
            ),
          ),
          Positioned(
            top: topInset,
            left: side + Space.screen,
            right: side + (actions.isEmpty ? Space.screen : Space.xs),
            height: _root,
            child: Row(
              children: [
                Expanded(child: Semantics(header: true, child: LargeTitle(title))),
                ...actions.map(_chrome),
              ],
            ),
          ),
        ],
      );
    }
    final t = (shrinkOffset / _large).clamp(0.0, 1.0);
    final solid = ((shrinkOffset - _large * 0.6) / (_large * 0.4)).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: solid,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xF209090A),
              border: Border(bottom: BorderSide(color: Palette.lineFaint)),
            ),
          ),
        ),
        Positioned(
          top: topInset,
          left: side,
          right: side,
          height: bar,
          child: Row(
            children: [
              if (canPop)
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const AppIconView(AppIcon.chevronLeft, color: Palette.ink),
                )
              else
                const SizedBox(width: Space.l),
              Expanded(
                child: Opacity(
                  opacity: t,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: TabPage.maxTitleScale,
                    child: Text(
                      title,
                      style: AppType.name.copyWith(fontSize: 16),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              ...actions.map(_chrome),
              SizedBox(width: actions.isEmpty ? (canPop ? 48 : Space.l) : Space.s),
            ],
          ),
        ),
        Positioned(
          left: side + Space.screen,
          right: side + Space.screen,
          bottom: 10 + 4 * t,
          child: Opacity(
            opacity: 1 - t,
            child: Semantics(header: true, child: LargeTitle(title)),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_Title old) =>
      old.title != title ||
      old.topInset != topInset ||
      old.canPop != canPop ||
      old.actions != actions ||
      old.side != side ||
      old.titleScale != titleScale;
}

/// A bar's control, holding its size once titles stop growing.
Widget _chrome(Widget action) => Builder(
  builder: (context) => MediaQuery.withClampedTextScaling(maxScaleFactor: TabPage.maxTitleScale, child: action),
);

/// Bar-like controls (segmented choices, a status in a title row) follow the text size only as far as titles do, as the
/// platforms' own controls do.
class BarScale extends StatelessWidget {
  const BarScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: TabPage.maxTitleScale, child: child);
}

/// A page's title in Archivo, following the user's text size up to [TabPage.maxTitleScale].
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: TabPage.maxTitleScale,
    child: Text(text, style: AppType.largeTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

/// A calm empty state: what is missing and the one way to fill it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.screen, Space.section, Space.screen, Space.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppType.title),
          const SizedBox(height: Space.s),
          Text(message, style: AppType.body.copyWith(color: Palette.inkSoft)),
          if (action != null) ...[const SizedBox(height: Space.xl), action!],
        ],
      ),
    );
  }
}
