import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/watch_controller.dart';
import '../../core/api.dart';
import '../../design/controls.dart';
import '../../design/face_disc.dart';
import '../../design/format.dart';
import '../../design/icons.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';
import '../common/installed_page.dart';
import '../setup/connect_sheets.dart';

/// My Watch: the face on the wrist, big, inside the bezel; swipe the bezel round through the other faces. Below it, how
/// safe the watch is and the one thing to do next.
///
/// The column spreads over the whole screen, the button seated just above the tab bar. On a tablet it stands centred;
/// on a phone turned on its side the face moves to the left and the rest sits beside it, so the button stays in view.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _shown = 0;
  String? _shownId;

  /// The faces to swipe through: the one on the wrist first, then the rest by name.
  List<WatchPackage> _faces(WatchController c) {
    final faces = [...c.faces]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final current = faces.indexWhere((f) => f.id == c.currentFaceId);
    if (current > 0) faces.insert(0, faces.removeAt(current));
    return faces;
  }

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    final faces = _faces(c);
    // Keep showing the same face when the list changes under it.
    final keep = _shownId == null ? -1 : faces.indexWhere((f) => f.id == _shownId);
    _shown = keep >= 0 ? keep : 0;
    final face = faces.isEmpty ? null : faces[_shown];
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    final side = TabPage.sideOf(context);
    final header = TabPage.titleRowOf(context);
    final sideways = size.width > size.height && size.height < 600;
    // As large as the screen allows, and never too small to read.
    final disc = sideways
        ? math.max(160.0, math.min(size.height - insets.top - insets.bottom - header - Space.l * 2, size.width * 0.42))
        : math.max(200.0, math.min(math.min(size.width * 0.9, 520.0), size.height * 0.44));
    final unsaved = {for (final p in c.notBackedUp) p.id};

    final bezel = SizedBox.square(
      dimension: disc,
      child: FaceDisc(
        faces: [
          for (final f in faces)
            DiscFace(id: f.id, name: f.name, picture: c.pictureOf(f.id) == null ? null : FileImage(c.pictureOf(f.id)!)),
        ],
        index: _shown,
        onChanged: (i) => setState(() {
          _shown = i;
          _shownId = faces[i].id;
        }),
        onTap: face == null ? null : () => _openFace(context, face),
        progress: c.operation?.progress,
        turns: c.presentations,
        dimmed: _asleep(c.phase),
        semanticHint: face == null ? null : 'Opens this face',
      ),
    );
    final rail = _Rail(controller: c, face: face, atRisk: unsaved.isNotEmpty);
    final name = _Name(controller: c, face: face, atRisk: face != null && unsaved.contains(face.id));
    final state = _State(controller: c);

    final Widget body;
    if (sideways) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(side + Space.s, Space.s, side + Space.screen, insets.bottom + Space.l),
        child: Row(
          children: [
            SizedBox(
              width: disc + 56,
              height: disc,
              child: Stack(
                children: [
                  Positioned(left: 0, top: 0, child: bezel),
                  Positioned(right: 4, top: disc / 2 - 80, child: rail),
                ],
              ),
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  name,
                  const SizedBox(height: Space.xl),
                  state,
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final column = EdgeInsets.symmetric(horizontal: side + Space.screen);
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            height: disc + Space.s,
            child: Stack(
              children: [
                Align(alignment: Alignment.topCenter, child: bezel),
                Positioned(right: math.max(4.0, (size.width - disc) / 2 - 16), top: disc / 2 - 80, child: rail),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          const _Gap(56),
          Padding(padding: column, child: name),
          const SizedBox(height: Space.xl),
          const _Gap(80),
          Padding(padding: column, child: state),
          SizedBox(height: insets.bottom + Space.xl),
        ],
      );
    }

    return RefreshIndicator.adaptive(
      onRefresh: c.address == null ? () async {} : c.refresh,
      color: Palette.ink,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: side),
              sliver: SliverToBoxAdapter(
                child: _Header(controller: c, height: header),
              ),
            ),
          ),
          SliverFillRemaining(hasScrollBody: false, child: body),
        ],
      ),
    );
  }

  static bool _asleep(LinkPhase phase) => switch (phase) {
    LinkPhase.notSetUp || LinkPhase.unreachable || LinkPhase.notAnswering || LinkPhase.failed => true,
    _ => false,
  };

  void _openFace(BuildContext context, WatchPackage face) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InstalledPage(package: face)));
}

/// Space that grows with the room the screen has, up to [max]; what is left over centres the column.
class _Gap extends StatelessWidget {
  const _Gap(this.max);

  final double max;

  @override
  Widget build(BuildContext context) => Flexible(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: max),
      child: const SizedBox.expand(),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.height});

  final WatchController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (text, color, pulse) = switch (c.phase) {
      LinkPhase.notSetUp => ('NOT SET UP', Palette.inkFaint, false),
      LinkPhase.connecting => ('CONNECTING', Palette.ink, true),
      LinkPhase.waitingForApproval => ('WAITING FOR YOU', Palette.ink, true),
      LinkPhase.connected => ('CONNECTED', Palette.ink, c.operation != null),
      LinkPhase.unreachable => ('OUT OF REACH', Palette.inkFaint, false),
      LinkPhase.notAnswering => ('NOT ANSWERING', Palette.inkFaint, false),
      LinkPhase.busy => ('BUSY', Palette.inkFaint, false),
      LinkPhase.failed => ('DISCONNECTED', Palette.inkFaint, false),
    };
    // The same place and size as every section's title row.
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: Space.screen),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Semantics(header: true, child: const LargeTitle('My Watch'))),
          const SizedBox(width: Space.m),
          BarScale(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
              // The demo watch is always there; saying it is the demo matters more than saying it is connected.
              child: c.services.demo
                  ? const DemoBadge()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusDot(color: color, pulse: pulse),
                        Flexible(
                          child: Text(
                            text,
                            style: AppType.label.copyWith(
                              color: color == Palette.inkFaint ? Palette.inkSoft : Palette.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rail: details of the face shown, the backup, and Discover.
class _Rail extends StatelessWidget {
  const _Rail({required this.controller, required this.face, required this.atRisk});

  final WatchController controller;
  final WatchPackage? face;
  final bool atRisk;

  @override
  Widget build(BuildContext context) {
    Widget button(AppIcon icon, String label, VoidCallback? onTap, {bool dot = false}) => IconButton(
      tooltip: label,
      onPressed: onTap,
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          AppIconView(icon, color: onTap == null ? Palette.inkFaint : Palette.ink, strokeWidth: 1.4),
          if (dot) const Positioned(right: -3, top: -2, child: RiskDot()),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          AppIcon.info,
          'About this face',
          face == null
              ? null
              : () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InstalledPage(package: face!))),
        ),
        const SizedBox(height: Space.s),
        button(
          AppIcon.backup,
          atRisk ? 'Backup: some faces and apps are not backed up' : 'Backup',
          () => SectionScope.goTo(context, Section.backup),
          dot: atRisk,
        ),
        const SizedBox(height: Space.s),
        button(AppIcon.discover, 'Discover faces', () => SectionScope.goTo(context, Section.discover)),
      ],
    );
  }
}

/// The face's name and one tracked line about it: where it is, and in red whether a reset would lose it.
class _Name extends StatelessWidget {
  const _Name({required this.controller, required this.face, required this.atRisk});

  final WatchController controller;
  final WatchPackage? face;
  final bool atRisk;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final op = c.operation;
    const risk = TextStyle(color: Palette.alert);
    final List<TextSpan> line;
    if (op != null) {
      line = [
        TextSpan(text: (op.progress >= 0 ? '${op.label} · ${(op.progress * 100).round()}%' : op.label).toUpperCase()),
      ];
    } else if (face == null) {
      line = [TextSpan(text: c.phase == LinkPhase.notSetUp ? 'NO WATCH YET' : 'YOUR WATCH')];
    } else {
      final wrist = face!.id == c.currentFaceId;
      // Non-breaking spaces keep each phrase whole when the line wraps at large text sizes.
      line = [
        if (wrist) TextSpan(text: atRisk ? 'ON\u00A0YOUR\u00A0WRIST · ' : 'ON\u00A0YOUR\u00A0WRIST'),
        if (atRisk) const TextSpan(text: 'NOT\u00A0BACKED\u00A0UP', style: risk),
        if (!wrist && !atRisk) const TextSpan(text: 'ON\u00A0YOUR\u00A0WATCH'),
      ];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The name follows the text size as far as titles do, so it never outgrows My Watch.
        BarScale(
          child: Text(
            face?.name ?? 'Galaxy Watch',
            style: AppType.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(style: AppType.label, children: line),
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }
}

/// What the watch needs now: setting up, approving this phone, or the two figures and the one button.
class _State extends StatelessWidget {
  const _State({required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: still ? Duration.zero : Motion.medium,
      switchInCurve: Motion.ease,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: _state(context, controller),
    );
  }

  Widget _state(BuildContext context, WatchController c) {
    if (c.phase == LinkPhase.notSetUp) return const _Setup(key: ValueKey('setup'));
    if (c.phase == LinkPhase.waitingForApproval) {
      return Column(
        key: const ValueKey('approve'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          const SizedBox(height: Space.l),
          Row(
            children: [
              const StatusDot(pulse: true),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  'Your watch asks to allow this phone. Tap the check mark on the watch.',
                  style: AppType.body,
                ),
              ),
            ],
          ),
        ],
      );
    }
    final risk = c.notBackedUp;
    final backup = c.latestBackup;
    final battery = c.status?.batteryPercent;
    final total = c.downloaded.length;
    final (String action, VoidCallback? onAction) = switch (c.problem) {
      final String _ => ('Try again', c.operation == null ? c.refresh : null),
      _ when backup == null || risk.isNotEmpty => (
        risk.isEmpty || backup == null
            ? 'Back up my watch'
            : 'Back up ${count(risk.length, 'face or app', 'faces and apps')}',
        c.phase == LinkPhase.connected && c.operation == null ? c.backUp : null,
      ),
      _ => ('Discover faces', () => SectionScope.goTo(context, Section.discover)),
    };
    return Column(
      key: const ValueKey('figures'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(),
        const SizedBox(height: Space.m),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Readout(value: battery == null ? '–' : '$battery%', label: 'Battery'),
              ),
              const VerticalDivider(width: Space.xxl),
              Expanded(
                child: Readout(
                  value: c.packages.isEmpty ? '–' : (backup == null ? '0/$total' : '${c.backedUpCount}/$total'),
                  label: 'Backed up',
                  risk: c.packages.isNotEmpty && (backup == null || risk.isNotEmpty),
                ),
              ),
            ],
          ),
        ),
        if (c.problem != null) ...[const SizedBox(height: Space.l), Text(c.problem!, style: AppType.secondary)],
        const SizedBox(height: Space.xl),
        AppButton(label: action, onPressed: onAction, expand: true),
      ],
    );
  }
}

/// The first run: the one switch the watch needs, how to find it, then connect.
class _Setup extends StatelessWidget {
  const _Setup({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(),
        const SizedBox(height: Space.l),
        Text(
          'Turn on Debugging on your watch, then connect over Wi-Fi.',
          style: AppType.secondary.copyWith(color: Palette.ink),
          textAlign: TextAlign.center,
        ),
        Center(
          child: TextButton(
            onPressed: () => showDebuggingHelp(context),
            style: TextButton.styleFrom(foregroundColor: Palette.ink, minimumSize: const Size(48, 44)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'How to turn on Debugging',
                    style: AppType.secondary.copyWith(
                      color: Palette.ink,
                      decoration: TextDecoration.underline,
                      decorationColor: Palette.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const AppIconView(AppIcon.chevronRight, color: Palette.ink, size: 16),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        AppButton(label: 'Connect my watch', onPressed: () => showFindWatchSheet(context), expand: true),
        const SizedBox(height: Space.s),
        AppButton(label: 'Type its address', filled: false, onPressed: () => showAddressSheet(context), expand: true),
      ],
    );
  }
}
