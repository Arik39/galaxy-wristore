import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/watch_controller.dart';
import '../../core/api.dart';
import '../../design/controls.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';
import '../common/installed_page.dart';
import '../common/pictures.dart';

/// The faces on the watch with their real pictures. The one on the wrist is ringed in white; one no backup has carries
/// a red dot.
class FacesScreen extends StatelessWidget {
  const FacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    final faces = [...c.faces]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final unsaved = {for (final p in c.notBackedUp) p.id};
    return TabPage(
      title: 'Faces',
      onRefresh: c.address == null ? null : c.refresh,
      slivers: [
        if (faces.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              title: c.packages.isEmpty ? 'Your faces show here' : 'No faces added yet',
              message: c.packages.isEmpty
                  ? 'Connect your watch and its faces appear here with their pictures.'
                  : 'Find faces in Tizen Archive and install them in one tap.',
              action: AppButton(
                label: c.packages.isEmpty ? 'Go to my watch' : 'Discover faces',
                onPressed: () => SectionScope.goTo(context, c.packages.isEmpty ? Section.watch : Section.discover),
              ),
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.screen, Space.m, Space.screen, 0),
            sliver: PictureGrid(
              maxTile: 190,
              lines: const [AppType.caption, AppType.label],
              gap: Space.m + 3,
              itemCount: faces.length,
              itemBuilder: (context, i) =>
                  _FaceTile(face: faces[i], controller: c, unsaved: unsaved.contains(faces[i].id)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.screen, Space.section, Space.screen, 0),
            sliver: SliverToBoxAdapter(
              child: AppButton(
                label: 'Find more faces',
                filled: false,
                expand: true,
                onPressed: () => SectionScope.goTo(context, Section.discover),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FaceTile extends StatelessWidget {
  const _FaceTile({required this.face, required this.controller, required this.unsaved});

  final WatchPackage face;
  final WatchController controller;
  final bool unsaved;

  @override
  Widget build(BuildContext context) {
    final current = controller.currentFaceId == face.id;
    return Semantics(
      button: true,
      label: '${face.name}${current ? ', on your wrist' : ''}${unsaved ? ', not backed up' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InstalledPage(package: face))),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PackagePicture(
                      name: face.name,
                      file: controller.pictureOf(face.id),
                      size: size,
                      ring: Palette.lineFaint,
                      bezel: current,
                    ),
                    if (unsaved) Positioned(right: size * 0.1, top: size * 0.1, child: const RiskDot(size: 11)),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.m),
            Text(
              face.name,
              style: AppType.caption.copyWith(color: Palette.ink),
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            if (current) ...[
              const SizedBox(height: 3),
              const Text('ON WRIST', style: AppType.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}
