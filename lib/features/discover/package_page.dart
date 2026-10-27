import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/app.dart';
import '../../app/watch_controller.dart';
import '../../core/api.dart';
import '../../design/controls.dart';
import '../../design/face_disc.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';
import '../common/picture_viewer.dart';
import 'discover_screen.dart';

/// One package of Tizen Archive, like a store page: a face in the bezel as the watch would show it (an app's icon
/// otherwise), what it is, the button that installs it, and its pictures. While it installs, the bezel's ticks light
/// up with the progress.
class PackagePage extends StatefulWidget {
  const PackagePage({super.key, required this.entry});

  final CatalogEntry entry;

  @override
  State<PackagePage> createState() => _PackagePageState();
}

class _PackagePageState extends State<PackagePage> {
  PackageDetails? _details;
  String? _error;
  Uint8List? _icon;
  List<Uint8List>? _pictures;
  bool _loadingPictures = false;
  String? _picturesNote;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    final catalog = WatchScope.read(context).services.catalog;
    catalog
        .details(widget.entry.id)
        .then(
          (d) {
            if (mounted) setState(() => _details = d);
          },
          onError: (Object e) {
            if (mounted) {
              setState(() => _error = e is CatalogException ? e.message : 'Tizen Archive could not be reached.');
            }
          },
        );
    catalogIcon(context, widget.entry.iconPath).then((bytes) {
      if (mounted) setState(() => _icon = bytes);
    });
  }

  /// Opens the package's pictures full size, loading them the first time.
  Future<void> _showPictures(String name) async {
    if (_pictures == null) await _loadPictures();
    final pictures = _pictures;
    if (!mounted || pictures == null || pictures.isEmpty) return;
    await showPictures(context, pictures, title: name);
  }

  /// The pictures are inside the package itself: it is downloaded, checked, read and deleted again.
  Future<void> _loadPictures() async {
    if (_loadingPictures) return;
    final services = WatchScope.read(context).services;
    setState(() {
      _loadingPictures = true;
      _picturesNote = null;
    });
    final temp = File(
      '${(await getTemporaryDirectory()).path}/wristore-pictures-${DateTime.now().microsecondsSinceEpoch}.pkg',
    );
    try {
      final info = await services.catalog.version(widget.entry.id);
      final choice = services.catalog.choose(info);
      final artifact = switch (choice) {
        ArtifactFound(:final artifact) => artifact,
        ArtifactNone() => info.artifacts.isEmpty ? null : info.artifacts.first,
      };
      if (artifact == null) {
        if (mounted) setState(() => _picturesNote = 'Tizen Archive has no file of this package to show pictures from.');
        return;
      }
      await services.catalog.download(artifact, temp);
      final images = await services.inspector.images(temp);
      if (mounted) {
        setState(() {
          _pictures = [for (final i in images) i.bytes];
          _picturesNote = images.isEmpty ? 'The package has no larger pictures.' : null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _picturesNote = 'The pictures could not be loaded: $e');
    } finally {
      if (temp.existsSync()) temp.deleteSync();
      if (mounted) setState(() => _loadingPictures = false);
    }
  }

  Future<void> _install(String name) async {
    setState(() => _installing = true);
    final controller = WatchScope.read(context);
    final failure = await controller.installFromCatalog(widget.entry.id, name);
    if (!mounted) return;
    setState(() => _installing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure ?? '$name is on your watch.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    final entry = widget.entry;
    final d = _details;
    final name = d?.name ?? entry.name;
    final latest = d?.latestVersion ?? entry.latestVersion;
    final onWatch = c.packages.where((p) => p.id == entry.id).firstOrNull;
    final face = entry.kind == CatalogKind.watchFace;
    final running = _installing ? c.operation : null;
    final width = MediaQuery.sizeOf(context).width;
    final refused = entry.verdict != Verdict.installable && entry.verdict != Verdict.unknown;
    return TabPage(
      title: name,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, Space.s, 0, Space.xl),
            child: Center(
              child: face
                  ? SizedBox.square(
                      dimension: (width * 0.74).clamp(220.0, 360.0),
                      child: FaceDisc(
                        faces: [
                          DiscFace(id: entry.id, name: name, picture: _icon == null ? null : MemoryImage(_icon!)),
                        ],
                        onTap: () => _showPictures(name),
                        progress: running?.progress,
                        turns: c.presentations,
                        semanticHint: 'Shows its pictures',
                      ),
                    )
                  : GestureDetector(
                      onTap: () => _showPictures(name),
                      child: CatalogIcon(entry: entry, round: false, size: 128, ring: Palette.line),
                    ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.screen),
          sliver: SliverList.list(
            children: [
              if (d?.authorName != null) SpecRow('Maker', d!.authorName!),
              SpecRow('Kind', face ? 'Watch face' : 'App'),
              if (latest != null) SpecRow('Version', latest),
              if (onWatch != null) SpecRow('On your watch', 'Version ${onWatch.version}'),
              const SizedBox(height: Space.xxl),
              _Install(
                onWatch: onWatch,
                latest: latest,
                connected: c.phase == LinkPhase.connected,
                running: running,
                installing: _installing,
                ticks: !face,
                onInstall: () => _install(name),
              ),
              if (refused) ...[
                const SizedBox(height: Space.m),
                Text(_verdictText(entry.verdict), style: AppType.caption.copyWith(color: Palette.alert)),
              ],
              if (_pictures == null || _pictures!.isNotEmpty) ...[
                const SizedBox(height: Space.s),
                AppButton(
                  label: _loadingPictures ? 'Loading its pictures' : 'See its pictures',
                  filled: false,
                  expand: true,
                  onPressed: _loadingPictures ? null : () => _showPictures(name),
                ),
              ],
              if (_picturesNote != null) ...[
                const SizedBox(height: Space.s),
                Text(_picturesNote!, style: AppType.secondary),
              ],
              if (_error != null) ...[const SizedBox(height: Space.xl), Text(_error!, style: AppType.secondary)],
              if ((d?.description ?? '').isNotEmpty) ...[
                const SizedBox(height: Space.section),
                const _Heading('About'),
                Text(d!.description!, style: AppType.body.copyWith(color: Palette.inkSoft)),
              ],
              if ((d?.versions.length ?? 0) > 1) ...[
                const SizedBox(height: Space.section),
                const _Heading('Versions'),
                for (final v in d!.versions.take(8))
                  SpecRow(v.version, v.verdict == Verdict.installable ? 'Installs' : _verdictShort(v.verdict)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _verdictText(Verdict v) => switch (v) {
    Verdict.deviceBound => 'It is signed for a few specific watches, so yours would likely refuse it.',
    Verdict.expired => 'Its signing certificate has expired, so watches refuse it.',
    Verdict.notInstallable => 'Watches refuse its signature.',
    Verdict.unverified => 'Nobody has confirmed yet that watches accept it.',
    _ => '',
  };

  static String _verdictShort(Verdict v) => switch (v) {
    Verdict.deviceBound => 'Specific watches only',
    Verdict.expired => 'Certificate expired',
    Verdict.notInstallable => 'Refused',
    Verdict.unverified => 'Not confirmed',
    _ => 'Unknown',
  };
}

/// A section's name in tracked capitals over a hairline.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(text.toUpperCase(), style: AppType.label.copyWith(color: Palette.inkSoft)),
          ),
          const SizedBox(height: Space.s),
          const Divider(),
        ],
      ),
    );
  }
}

/// The install button, or what the install is doing while it runs.
class _Install extends StatelessWidget {
  const _Install({
    required this.onWatch,
    required this.latest,
    required this.connected,
    required this.running,
    required this.installing,
    required this.ticks,
    required this.onInstall,
  });

  final WatchPackage? onWatch;
  final String? latest;
  final bool connected;
  final Operation? running;
  final bool installing;

  /// Off for a face, whose bezel above already lights its ticks.
  final bool ticks;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    if (installing) {
      return JobProgress(label: running?.label ?? 'Getting ready', progress: running?.progress ?? -1, ticks: ticks);
    }
    final current = onWatch;
    if (current != null && (latest == null || current.version == latest)) {
      return Row(
        children: [
          const StatusDot(),
          const SizedBox(width: Space.xs),
          Text('ON YOUR WATCH', style: AppType.label.copyWith(color: Palette.ink)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: current == null ? 'Install on my watch' : 'Update to $latest',
          onPressed: connected ? onInstall : null,
          expand: true,
        ),
        if (!connected)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              'Connect your watch on the Watch tab to install.',
              style: AppType.caption,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
