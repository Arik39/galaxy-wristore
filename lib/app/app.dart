import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/controls.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../core/api.dart';
import '../features/apps/apps_screen.dart';
import '../features/backup/backup_screen.dart';
import '../features/backup/restore_page.dart';
import '../features/common/installed_page.dart';
import '../features/discover/discover_screen.dart';
import '../features/discover/package_page.dart';
import '../features/faces/faces_screen.dart';
import '../features/home/home_screen.dart';
import '../features/watch/watch_settings_page.dart';
import 'theme.dart';
import 'watch_controller.dart';

/// Gives every screen the [WatchController] and rebuilds them when it changes.
class WatchScope extends InheritedNotifier<WatchController> {
  const WatchScope({super.key, required WatchController controller, required super.child})
    : super(notifier: controller);

  static WatchController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WatchScope>()!.notifier!;

  /// The controller without listening, for actions in callbacks.
  static WatchController read(BuildContext context) => context.getInheritedWidgetOfExactType<WatchScope>()!.notifier!;
}

/// The app's sections, in tab order.
enum Section { watch, faces, apps, discover, backup }

/// Lets a screen switch sections, e.g. a hotspot on the watch leading to its faces.
class SectionScope extends InheritedWidget {
  const SectionScope({super.key, required this.go, required super.child});

  final void Function(Section section) go;

  static void goTo(BuildContext context, Section section) =>
      context.getInheritedWidgetOfExactType<SectionScope>()!.go(section);

  @override
  bool updateShouldNotify(SectionScope old) => false;
}

class GalaxyWristoreApp extends StatelessWidget {
  const GalaxyWristoreApp({super.key, required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    return WatchScope(
      controller: controller,
      child: MaterialApp(
        title: 'Galaxy Wristore',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        themeMode: ThemeMode.dark,
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
          child: Backdrop(child: child!),
        ),
        home: const Shell(),
      ),
    );
  }
}

/// The tabs. Each section keeps its own navigation stack, so a detail page opened in Discover is still there after a
/// look at the watch.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  /// The tab to open on, for screenshots of each section (`--dart-define=WRISTORE_TAB=faces`); the Watch tab otherwise.
  static const _initialTab = String.fromEnvironment('WRISTORE_TAB');

  /// A page to open on start, also for screenshots (`--dart-define=WRISTORE_OPEN=face`): `face`, `app`, `package`,
  /// `restore` or `settings`, opened once the watch's state allows it.
  static const _initialPage = String.fromEnvironment('WRISTORE_OPEN');

  Section _section = Section.values.firstWhere((s) => s.name == _initialTab, orElse: () => Section.watch);
  final _navigators = {for (final s in Section.values) s: GlobalKey<NavigatorState>()};
  WatchController? _waiting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialPage.isNotEmpty && _waiting == null) {
      _waiting = WatchScope.read(context)..addListener(_openInitialPage);
      _openInitialPage();
    }
  }

  @override
  void dispose() {
    _waiting?.removeListener(_openInitialPage);
    super.dispose();
  }

  Future<void> _openInitialPage() async {
    final c = _waiting!;
    final navigator = _navigators[_section]!.currentState;
    if (navigator == null || c.operation != null) return;
    Widget? page;
    switch (_initialPage) {
      case 'face' when c.faces.isNotEmpty:
        page = InstalledPage(package: c.faces.firstWhere((f) => f.id == c.currentFaceId, orElse: () => c.faces.first));
      case 'app' when c.apps.isNotEmpty:
        page = InstalledPage(
          package: c.apps.firstWhere((a) => a.origin == PackageOrigin.downloaded, orElse: () => c.apps.first),
        );
      case 'restore' when c.backups.isNotEmpty:
        page = RestorePage(record: c.backups.first);
      case 'settings' when c.phase == LinkPhase.connected:
        page = const WatchSettingsPage();
      case 'package':
        c.removeListener(_openInitialPage);
        final found = await c.services.catalog.search(kind: CatalogKind.watchFace);
        if (found.items.isNotEmpty && mounted) page = PackagePage(entry: found.items.first);
    }
    if (page == null) return;
    c.removeListener(_openInitialPage);
    navigator.push(MaterialPageRoute<void>(builder: (_) => page!));
  }

  static const _labels = {
    Section.watch: 'Watch',
    Section.faces: 'Faces',
    Section.apps: 'Apps',
    Section.discover: 'Discover',
    Section.backup: 'Backup',
  };
  static const _icons = {
    Section.watch: AppIcon.watch,
    Section.faces: AppIcon.faces,
    Section.apps: AppIcon.apps,
    Section.discover: AppIcon.discover,
    Section.backup: AppIcon.backup,
  };

  void _go(Section section) {
    if (section == _section) {
      // Tapping the open tab goes back to its first screen.
      _navigators[section]!.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _section = section);
  }

  Widget _root(Section s) => switch (s) {
    Section.watch => const HomeScreen(),
    Section.faces => const FacesScreen(),
    Section.apps => const AppsScreen(),
    Section.discover => const DiscoverScreen(),
    Section.backup => const BackupScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final stack = IndexedStack(
      index: _section.index,
      children: [
        for (final s in Section.values)
          TickerMode(
            enabled: s == _section,
            child: NavigatorPopHandler(
              onPopWithResult: (_) => _navigators[s]!.currentState?.maybePop(),
              child: Navigator(
                key: _navigators[s],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: (_) => _root(s)),
              ),
            ),
          ),
      ],
    );
    return SectionScope(
      go: _go,
      child: Scaffold(extendBody: true, body: stack, bottomNavigationBar: ios ? _cupertinoBar() : _materialBar()),
    );
  }

  // Icons only, the open one marked with a dot beneath; the labels stay for screen readers and tooltips.
  static Widget _selected(AppIcon icon) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppIconView(icon, color: Palette.ink),
      const SizedBox(height: 5),
      Container(
        width: 4,
        height: 4,
        decoration: const BoxDecoration(color: Palette.ink, shape: BoxShape.circle),
      ),
    ],
  );

  Widget _cupertinoBar() => CupertinoTabBar(
    currentIndex: _section.index,
    onTap: (i) => _go(Section.values[i]),
    backgroundColor: Palette.void_,
    activeColor: Palette.ink,
    inactiveColor: Palette.inkFaint,
    border: const Border(top: BorderSide(color: Palette.lineFaint)),
    height: 56,
    items: [
      for (final s in Section.values)
        BottomNavigationBarItem(
          icon: Semantics(
            label: _labels[s],
            child: AppIconView(_icons[s]!, color: Palette.inkFaint),
          ),
          activeIcon: Semantics(label: _labels[s], child: _selected(_icons[s]!)),
          tooltip: _labels[s],
        ),
    ],
  );

  Widget _materialBar() => NavigationBar(
    selectedIndex: _section.index,
    onDestinationSelected: (i) => _go(Section.values[i]),
    destinations: [
      for (final s in Section.values)
        NavigationDestination(
          icon: AppIconView(_icons[s]!, color: Palette.inkFaint),
          selectedIcon: _selected(_icons[s]!),
          label: _labels[s]!,
          tooltip: _labels[s],
        ),
    ],
  );
}
