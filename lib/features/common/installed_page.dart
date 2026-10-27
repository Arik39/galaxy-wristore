import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/watch_controller.dart';
import '../../core/api.dart';
import '../../core/catalog/version_compare.dart';
import '../../design/controls.dart';
import '../../design/face_disc.dart';
import '../../design/format.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';
import 'picture_viewer.dart';
import 'pictures.dart';

/// One face or app on the watch: its picture as the watch shows it, what it is, whether a backup has it, whether Tizen
/// Archive has a newer version, and what can be done with it. Tapping the picture opens it full size.
class InstalledPage extends StatefulWidget {
  const InstalledPage({super.key, required this.package});

  final WatchPackage package;

  @override
  State<InstalledPage> createState() => _InstalledPageState();
}

/// What Tizen Archive says about a package on the watch.
sealed class _Archive {
  const _Archive();
}

class _Checking extends _Archive {
  const _Checking();
}

class _NotInArchive extends _Archive {
  const _NotInArchive();
}

class _Unreachable extends _Archive {
  const _Unreachable();
}

class _Found extends _Archive {
  const _Found(this.latest, {required this.installable});

  final String? latest;

  /// Whether watches are known to accept the latest version, or nobody has said otherwise.
  final bool installable;
}

class _InstalledPageState extends State<InstalledPage> {
  _Archive _archive = const _Checking();
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final catalog = WatchScope.read(context).services.catalog;
    try {
      final details = await catalog.details(widget.package.id);
      final latest = details.latestVersion;
      final verdict = details.versions.where((v) => v.version == latest).firstOrNull?.verdict ?? Verdict.unknown;
      if (mounted) {
        setState(
          () => _archive = _Found(latest, installable: verdict == Verdict.installable || verdict == Verdict.unknown),
        );
      }
    } on CatalogException catch (e) {
      if (mounted) setState(() => _archive = e.statusCode == 404 ? const _NotInArchive() : const _Unreachable());
    } on Exception {
      if (mounted) setState(() => _archive = const _Unreachable());
    }
  }

  Future<void> _update(WatchController c, WatchPackage p, String version) async {
    setState(() => _updating = true);
    final failure = await c.installFromCatalog(p.id, p.name);
    if (!mounted) return;
    setState(() => _updating = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure ?? '${p.name} is updated to version $version.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    // The watch's own record, so a version just updated shows at once.
    final p = c.packages.where((x) => x.id == widget.package.id).firstOrNull ?? widget.package;
    final face = WatchController.kindOf(p) == PackageKind.watchFace;
    final added = p.origin == PackageOrigin.downloaded;
    final unsaved = c.notBackedUp.any((n) => n.id == p.id);
    // Tizen Archive has no copy of it: a reset would remove it, and backing up again would not help.
    final unsaveable = c.unsaveable.any((n) => n.id == p.id);
    final backup = c.latestBackup;
    final picture = c.pictureOf(p.id);
    final ready = c.phase == LinkPhase.connected && c.operation == null;
    final width = MediaQuery.sizeOf(context).width;
    final view = picture == null ? null : () => _view(context, p, picture);
    final archive = _archive;
    final newer = archive is _Found && archive.latest != null && VersionCompare.isNewer(archive.latest!, p.version)
        ? archive.latest
        : null;
    final canUpdate = newer != null && (archive as _Found).installable;
    final running = _updating ? c.operation : null;
    return TabPage(
      title: p.name,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, Space.s, 0, Space.xl),
            child: Center(
              child: face
                  ? SizedBox.square(
                      dimension: (width * 0.8).clamp(220.0, 380.0),
                      child: FaceDisc(
                        faces: [DiscFace(id: p.id, name: p.name, picture: picture == null ? null : FileImage(picture))],
                        onTap: view,
                        progress: c.operation?.progress,
                        turns: c.presentations,
                        semanticHint: 'Opens it full size',
                      ),
                    )
                  : GestureDetector(
                      onTap: view,
                      child: PackagePicture(name: p.name, file: picture, size: 128, ring: Palette.line),
                    ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.screen),
          sliver: SliverList.list(
            children: [
              SpecRow('Version', p.version),
              SpecRow('Source', switch (p.origin) {
                PackageOrigin.downloaded => 'Added by you',
                PackageOrigin.builtInUpdated => 'Came with the watch, updated',
                _ => 'Came with the watch',
              }),
              SpecRow(
                'Backup',
                !added
                    ? 'A reset keeps it'
                    : unsaved || backup == null
                    ? (unsaveable ? 'Cannot be backed up' : 'Not backed up')
                    : formatWhen(backup.createdAt),
                risk: added && unsaved,
              ),
              SpecRow('Tizen Archive', switch (archive) {
                _Checking() => 'Checking',
                _NotInArchive() => 'Not in the archive',
                _Unreachable() => 'Could not be checked',
                _Found() when newer != null =>
                  canUpdate ? 'Version $newer available' : 'Version $newer, not installable',
                _Found() => 'Up to date',
              }),
              // Faces are worn and customized on the watch: the debugging link can do neither.
              if (face)
                Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Text(
                    p.id == c.currentFaceId
                        ? 'To customize it, touch and hold it on your watch.'
                        : 'To wear it, touch and hold the face on your watch, then swipe to it and tap.',
                    style: AppType.caption.copyWith(color: Palette.inkSoft),
                  ),
                ),
              if (unsaved || added || canUpdate) const SizedBox(height: Space.xxl),
              // White is kept for one button: backing up comes first while the backup lacks this.
              if (unsaved && !unsaveable) ...[
                AppButton(label: 'Back up now', onPressed: ready ? c.backUp : null, expand: true),
                const SizedBox(height: Space.s),
              ],
              if (running != null) ...[
                JobProgress(label: running.label, progress: running.progress, ticks: !face),
                const SizedBox(height: Space.s),
              ] else if (canUpdate) ...[
                AppButton(
                  label: 'Update to $newer',
                  filled: !unsaved || unsaveable,
                  expand: true,
                  onPressed: ready ? () => _update(c, p, newer) : null,
                ),
                const SizedBox(height: Space.s),
              ],
              if (added)
                AppButton(
                  label: 'Remove from watch',
                  filled: false,
                  color: Palette.alert,
                  expand: true,
                  onPressed: ready ? () => _remove(context, c, p, unsaved) : null,
                ),
              if ((added || canUpdate) && c.phase != LinkPhase.connected)
                Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Text(
                    'Connect your watch to change what is on it.',
                    style: AppType.caption,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _view(BuildContext context, WatchPackage p, File picture) async {
    final bytes = await picture.readAsBytes();
    if (context.mounted) await showPictures(context, [bytes], title: p.name);
  }

  Future<void> _remove(BuildContext context, WatchController c, WatchPackage p, bool unsaved) async {
    final sure = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialog) => AlertDialog(
        title: Text('Remove ${p.name}?', style: AppType.title),
        content: Text(
          unsaved
              ? 'It is not in a backup, and its data on the watch goes too. Tizen Archive may not have it any more.'
              : 'Its data on the watch goes too. Your backup keeps a copy to put back.',
          style: AppType.body.copyWith(color: Palette.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(foregroundColor: Palette.ink, textStyle: AppType.button),
            child: const Text('KEEP IT'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: Palette.alert, textStyle: AppType.button),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final result = await c.uninstall(p);
    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? '${p.name} is removed from your watch.'
              : 'The watch kept ${p.name}: ${result.message ?? result.code ?? 'no reason given'}.',
        ),
      ),
    );
    if (result.success) Navigator.of(context).maybePop();
  }
}
