import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/watch_controller.dart';
import '../../core/api.dart';
import '../../design/controls.dart';
import '../../design/format.dart';
import '../../design/icons.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';
import '../common/picture_viewer.dart';
import '../common/pictures.dart';

/// Choosing what of a backup goes back onto the watch, one by one, with each face's pictures full size. Nothing is
/// ticked at first: only what the user picks is put back.
class RestorePage extends StatefulWidget {
  const RestorePage({super.key, required this.record});

  final BackupRecord record;

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  BackupContents? _contents;
  String? _error;
  final _packages = <String>{};
  final _files = <String>{};
  final _thumbnails = <String, Uint8List?>{};
  bool _showFiles = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    WatchScope.read(context).services.backups
        .open(widget.record.file!)
        .then(
          (contents) {
            if (!mounted) {
              contents.close();
              return;
            }
            setState(() => _contents = contents);
            for (final item in contents.items) {
              contents.thumbnail(item).then((bytes) {
                if (mounted) setState(() => _thumbnails[item.package.id] = bytes);
              });
            }
          },
          onError: (Object e) {
            if (mounted) setState(() => _error = 'This backup cannot be opened: $e');
          },
        );
  }

  @override
  void dispose() {
    _contents?.close();
    super.dispose();
  }

  Future<void> _showPicturesOf(BackupItem item) async {
    final pictures = await _contents!.pictures(item);
    if (!mounted) return;
    if (pictures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The backup has no picture of it.')));
      return;
    }
    await showPictures(context, pictures, title: item.package.name);
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final controller = WatchScope.read(context);
    final result = await controller.restore(widget.record.file!, packageIds: {..._packages}, mediaPaths: {..._files});
    if (!mounted) return;
    setState(() => _restoring = false);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result == null ? 'The restore did not finish' : 'Put back', style: AppType.title),
              const SizedBox(height: Space.m),
              if (result == null)
                Text(controller.problem ?? 'Your watch could not be reached.', style: AppType.body)
              else ...[
                if (result.installed.isNotEmpty)
                  Text('Installed: ${listNames(result.installed, max: 4)}', style: AppType.body),
                if (result.alreadyThere.isNotEmpty)
                  Text('Already on the watch: ${listNames(result.alreadyThere, max: 4)}', style: AppType.secondary),
                if (result.filesCopied > 0) Text('Files copied back: ${result.filesCopied}', style: AppType.body),
                if (result.failed.isNotEmpty) ...[
                  const SizedBox(height: Space.m),
                  Text('NOT PUT BACK', style: AppType.label.copyWith(color: Palette.alert)),
                  const SizedBox(height: Space.xs),
                  for (final f in result.failed) Text(f, style: AppType.secondary),
                ],
                if (result.filesCopied > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.m),
                    child: Text(
                      'Music and pictures may show in their apps after the watch restarts.',
                      style: AppType.caption,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contents = _contents;
    final record = widget.record;
    final chosen = _packages.length + _files.length;
    return TabPage(
      title: 'Restore',
      actions: [
        if (contents != null)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Palette.ink,
              textStyle: AppType.button,
              minimumSize: const Size(48, 44),
            ),
            onPressed: () => setState(() {
              final all = _showFiles
                  ? {for (final m in contents.manifest.media) m.path}
                  : {for (final i in contents.items) i.package.id};
              final target = _showFiles ? _files : _packages;
              target.length == all.length ? target.clear() : target.addAll(all);
            }),
            child: Text(_allChosen ? 'NONE' : 'ALL'),
          ),
      ],
      bottom: contents == null ? null : _bottomBar(chosen),
      slivers: contents == null
          ? [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Space.section),
                  child: Center(
                    child: _error == null
                        ? const CircularProgressIndicator.adaptive()
                        : Text(_error!, style: AppType.body),
                  ),
                ),
              ),
            ]
          : [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.m),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'From your backup of ${formatWhen(record.createdAt).toLowerCase()}',
                        style: AppType.secondary,
                      ),
                      const SizedBox(height: Space.l),
                      BarScale(
                        child: SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(value: false, label: Text('FACES & APPS · ${contents.items.length}')),
                            ButtonSegment(value: true, label: Text('FILES · ${contents.manifest.media.length}')),
                          ],
                          selected: {_showFiles},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => setState(() => _showFiles = s.first),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showFiles) ..._fileList(contents) else ..._packageList(contents),
            ],
    );
  }

  bool get _allChosen {
    final contents = _contents;
    if (contents == null) return false;
    return _showFiles ? _files.length == contents.manifest.media.length : _packages.length == contents.items.length;
  }

  List<Widget> _packageList(BackupContents contents) {
    final noCopy = contents.manifest.packages.where((p) => p.entry == null).toList();
    // Where each copy came from is worth a word only when it differs between them.
    final mixed = {for (final i in contents.items) i.package.source}.length > 1;
    return [
      SliverList.builder(
        itemCount: contents.items.length,
        itemBuilder: (context, i) {
          final item = contents.items[i];
          return _ChoiceRow(
            chosen: _packages.contains(item.package.id),
            onChanged: (v) => setState(() => v ? _packages.add(item.package.id) : _packages.remove(item.package.id)),
            leading: Semantics(
              button: true,
              label: 'Pictures of ${item.package.name}',
              child: GestureDetector(
                onTap: () => _showPicturesOf(item),
                child: PackagePicture(
                  name: item.package.name,
                  bytes: _thumbnails[item.package.id],
                  round: item.kind == PackageKind.watchFace,
                  size: 52,
                ),
              ),
            ),
            title: item.package.name,
            detail: [
              item.kind == PackageKind.watchFace ? 'Face' : 'App',
              'version ${item.package.entryVersion ?? item.package.version}',
              if (mixed && item.package.source != null) item.package.source!,
            ].join(' · '),
          );
        },
      ),
      if (noCopy.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.screen, Space.xl, Space.screen, 0),
            child: Text(
              'No copy in this backup: ${listNames([for (final p in noCopy) p.name], max: 6)}.',
              style: AppType.caption,
            ),
          ),
        ),
    ];
  }

  List<Widget> _fileList(BackupContents contents) {
    final media = contents.manifest.media;
    if (media.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(Space.screen),
            child: Text('This backup has no files from the watch.', style: AppType.secondary),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: media.length,
        itemBuilder: (context, i) {
          final m = media[i];
          final name = m.path.split('/').last;
          return _ChoiceRow(
            chosen: _files.contains(m.path),
            onChanged: (v) => setState(() => v ? _files.add(m.path) : _files.remove(m.path)),
            leading: null,
            title: name,
            detail: '${formatBytes(m.size)} · ${m.path.split('/').reversed.skip(1).first}',
            onPreview: RegExp(r'\.(png|jpe?g|gif|bmp)$', caseSensitive: false).hasMatch(m.path)
                ? () async {
                    final bytes = await contents.mediaBytes(m);
                    if (bytes != null && context.mounted) await showPictures(context, [bytes], title: name);
                  }
                : null,
          );
        },
      ),
    ];
  }

  Widget _chosenBar(int chosen, bool ready, bool connected) => _chosenBarLayout(
    context,
    Text(
      chosen == 0
          ? (connected ? 'Tick what to put back' : 'Connect your watch to put things back')
          : '${count(chosen, 'item')} chosen',
      style: AppType.secondary.copyWith(color: Palette.ink),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    AppButton(label: 'Put back', onPressed: ready ? _restore : null),
  );

  Widget _bottomBar(int chosen) {
    final c = WatchScope.of(context);
    final ready = chosen > 0 && !_restoring && c.phase == LinkPhase.connected && c.operation == null;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.void_,
        border: Border(top: BorderSide(color: Palette.lineFaint)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Space.screen,
          Space.m,
          Space.screen,
          Space.m + MediaQuery.paddingOf(context).bottom,
        ),
        child: _restoring
            ? JobProgress(label: c.operation?.label ?? 'Restoring', progress: c.operation?.progress ?? -1)
            : _chosenBar(chosen, ready, c.phase == LinkPhase.connected),
      ),
    );
  }
}

/// What is chosen and the Put back button: side by side, or stacked when the text is set very large.
Widget _chosenBarLayout(BuildContext context, Widget text, Widget button) {
  if (MediaQuery.textScalerOf(context).scale(14) > 22) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        const SizedBox(height: Space.s),
        button,
      ],
    );
  }
  return Row(
    children: [
      Expanded(child: text),
      const SizedBox(width: Space.m),
      button,
    ],
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.chosen,
    required this.onChanged,
    required this.leading,
    required this.title,
    required this.detail,
    this.onPreview,
  });

  final bool chosen;
  final ValueChanged<bool> onChanged;
  final Widget? leading;
  final String title;
  final String detail;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!chosen),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.s, Space.xs),
        child: Row(
          children: [
            Semantics(
              checked: chosen,
              child: SizedBox(
                width: 44,
                height: 48,
                child: Center(child: _Tick(chosen: chosen)),
              ),
            ),
            if (leading != null) ...[leading!, const SizedBox(width: Space.m)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(detail, style: AppType.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onPreview != null)
              IconButton(
                tooltip: 'View',
                onPressed: onPreview,
                icon: const AppIconView(AppIcon.search, color: Palette.inkSoft, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

/// A round mark for a chosen row: a hairline circle, filled white with a check once chosen.
class _Tick extends StatelessWidget {
  const _Tick({required this.chosen});

  final bool chosen;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.short,
      curve: Motion.ease,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: chosen ? Palette.ink : Colors.transparent,
        border: Border.all(color: chosen ? Palette.ink : Palette.inkSoft, width: 1.5),
      ),
      child: AnimatedOpacity(
        opacity: chosen ? 1 : 0,
        duration: Motion.short,
        child: const AppIconView(AppIcon.check, size: 16, color: Palette.void_, strokeWidth: 2.2),
      ),
    );
  }
}
