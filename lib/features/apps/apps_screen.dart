import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/watch_controller.dart';
import '../../core/api.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';
import '../common/installed_page.dart';
import '../common/pictures.dart';

/// The apps on the watch: the ones you added, then the ones it came with.
class AppsScreen extends StatelessWidget {
  const AppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    int byName(WatchPackage a, WatchPackage b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    final added = [
      for (final p in c.apps)
        if (p.origin == PackageOrigin.downloaded) p,
    ]..sort(byName);
    final builtIn = [
      for (final p in c.apps)
        if (p.origin != PackageOrigin.downloaded) p,
    ]..sort(byName);
    final unsaved = {for (final p in c.notBackedUp) p.id};
    return TabPage(
      title: 'Apps',
      onRefresh: c.address == null ? null : c.refresh,
      slivers: [
        if (c.packages.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              title: 'Your apps show here',
              message: 'Connect your watch and its apps appear here.',
              action: AppButton(label: 'Go to my watch', onPressed: () => SectionScope.goTo(context, Section.watch)),
            ),
          )
        else ...[
          SliverToBoxAdapter(child: SectionHeader('Added by you · ${added.length}')),
          if (added.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.screen, Space.s, Space.screen, 0),
                child: Text('None yet. Discover has the archive of watch apps.', style: AppType.secondary),
              ),
            ),
          SliverList.builder(
            itemCount: added.length,
            itemBuilder: (context, i) => _AppRow(app: added[i], controller: c, unsaved: unsaved.contains(added[i].id)),
          ),
          SliverToBoxAdapter(child: SectionHeader('Came with the watch · ${builtIn.length}')),
          SliverList.builder(
            itemCount: builtIn.length,
            itemBuilder: (context, i) => _AppRow(app: builtIn[i], controller: c, unsaved: false),
          ),
        ],
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.controller, required this.unsaved});

  final WatchPackage app;
  final WatchController controller;
  final bool unsaved;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${app.name}, version ${app.version}${unsaved ? ', not backed up' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InstalledPage(package: app))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.screen, Space.m, Space.l, Space.m),
          child: Row(
            children: [
              PackagePicture(name: app.name, file: controller.pictureOf(app.id), size: 44),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.name, style: AppType.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    if (unsaved)
                      Text('NOT\u00A0BACKED\u00A0UP', style: AppType.label.copyWith(color: Palette.alert), maxLines: 2)
                    else
                      Text(
                        'Version ${app.version}',
                        style: AppType.caption.copyWith(color: Palette.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const AppIconView(AppIcon.chevronRight, color: Palette.inkFaint, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
