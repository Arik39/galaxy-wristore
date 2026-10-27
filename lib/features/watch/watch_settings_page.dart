import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/watch_controller.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';

/// The watch's own settings, reached from the phone. Over Debugging the watch lets its screens be opened but not its
/// settings be changed, so each row opens that screen on the watch, where the change is made. At the top, ringing the
/// watch to find it.
class WatchSettingsPage extends StatelessWidget {
  const WatchSettingsPage({super.key});

  /// Screens confirmed to open on a Galaxy Watch (SM-R800, Tizen 5.5), by the app id the watch launches.
  static const groups = <(String, List<(String, String)>, String?)>[
    (
      'Sound and vibration',
      [
        ('Sound', 'com.samsung.clocksetting.sound'),
        ('Volume', 'com.samsung.clocksetting.sound-volume'),
        ('Ringtones and tones', 'com.samsung.clocksetting.sound-tone-list'),
      ],
      null,
    ),
    (
      'Notifications',
      [('Notifications', 'com.samsung.wnotification2'), ('Do not disturb', 'com.samsung.clocksetting.do-not-disturb')],
      "Which phone apps notify your watch is chosen in Samsung's app on the phone.",
    ),
    (
      'Display',
      [('Display', 'com.samsung.clocksetting.display')],
      'To change or customize your face, touch and hold it on your watch.',
    ),
    (
      'Arrange',
      [('Quick settings', 'com.samsung.windicator-editor'), ('Apps view', 'com.samsung.w-home.setting-view-by')],
      'To move apps and widgets, touch and hold them on your watch.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    final connected = c.phase == LinkPhase.connected;
    return TabPage(
      title: 'Watch settings',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.screen),
          sliver: SliverToBoxAdapter(child: _Ring(controller: c)),
        ),
        for (final (title, rows, note) in groups) ...[
          SliverToBoxAdapter(child: SectionHeader(title)),
          SliverList.list(
            children: [for (final (name, appId) in rows) _OpenRow(name: name, appId: appId, controller: c)],
          ),
          if (note != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.screen, Space.xs, Space.screen, 0),
                child: Text(note, style: AppType.caption.copyWith(color: Palette.inkFaint)),
              ),
            ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.screen, Space.xxl, Space.screen, 0),
            child: Row(
              children: [
                const AppIconView(AppIcon.openOut, color: Palette.inkFaint, size: 16),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    connected ? 'Opens on your watch.' : 'Connect your watch on the Watch tab to use these.',
                    style: AppType.caption.copyWith(color: Palette.inkFaint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Find my watch: the ring button, or what is happening while the watch rings.
class _Ring extends StatelessWidget {
  const _Ring({required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ready = c.phase == LinkPhase.connected && c.operation == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.s),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.short,
          child: c.ringing
              ? Column(
                  key: const ValueKey('ringing'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const JobProgress(label: 'Ringing your watch', progress: -1),
                    const SizedBox(height: Space.m),
                    AppButton(label: 'Stop', onPressed: c.stopRinging, expand: true),
                  ],
                )
              : AppButton(
                  key: const ValueKey('ring'),
                  label: 'Ring my watch',
                  onPressed: ready ? c.ring : null,
                  expand: true,
                ),
        ),
        const SizedBox(height: Space.s),
        Text(
          'It plays its find tone for up to a minute, while it is on the same Wi-Fi as this phone.',
          style: AppType.caption.copyWith(color: Palette.inkFaint),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A row that opens one of the watch's screens.
class _OpenRow extends StatefulWidget {
  const _OpenRow({required this.name, required this.appId, required this.controller});

  final String name;
  final String appId;
  final WatchController controller;

  @override
  State<_OpenRow> createState() => _OpenRowState();
}

class _OpenRowState extends State<_OpenRow> {
  bool _opening = false;

  Future<void> _open() async {
    setState(() => _opening = true);
    final failure = await widget.controller.openOnWatch(widget.appId);
    if (!mounted) return;
    setState(() => _opening = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure ?? '${widget.name} is open on your watch.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = c.phase == LinkPhase.connected && c.operation == null;
    return Semantics(
      button: true,
      enabled: ready,
      label: '${widget.name}, opens on your watch',
      excludeSemantics: true,
      child: InkWell(
        onTap: ready ? _open : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.screen, Space.m, Space.screen, Space.m),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.name,
                  style: AppType.body.copyWith(color: ready || _opening ? Palette.ink : Palette.inkFaint),
                ),
              ),
              if (_opening)
                const StatusDot(pulse: true)
              else
                AppIconView(AppIcon.openOut, color: ready ? Palette.inkSoft : Palette.inkFaint, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
