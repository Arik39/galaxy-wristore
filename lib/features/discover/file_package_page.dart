import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
import '../common/pictures.dart';

/// Lets the user pick a `.tpk` or `.wgt` file they have and opens it on a [FilePackagePage].
Future<void> pickPackageFile(BuildContext context) async {
  final picked = await FilePicker.pickFiles(dialogTitle: 'Choose a watch package');
  final path = picked.isEmpty ? null : picked.first.path;
  if (path == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FilePackagePage(file: File(path))));
}

/// A package file of the user's: what it is, whether its signature will likely satisfy the watch, and the button that
/// installs it. The watch has the last word: a doubtful signature is said plainly, but never blocks the install.
class FilePackagePage extends StatefulWidget {
  const FilePackagePage({super.key, required this.file});

  final File file;

  @override
  State<FilePackagePage> createState() => _FilePackagePageState();
}

class _FilePackagePageState extends State<FilePackagePage> {
  TizenPackageInfo? _info;
  SignatureVerdict? _verdict;
  List<Uint8List> _pictures = const [];
  String? _error;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final inspector = WatchScope.read(context).services.inspector;
    try {
      final info = await inspector.read(widget.file);
      final verdict = await inspector.signature(widget.file);
      final images = await inspector.images(widget.file, maxImages: 8);
      if (!mounted) return;
      setState(() {
        _info = info;
        _verdict = verdict;
        _pictures = [for (final i in images) i.bytes];
      });
    } on InvalidPackageException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'It could not be read: $e');
    }
  }

  Future<void> _install(String name) async {
    setState(() => _installing = true);
    final controller = WatchScope.read(context);
    final result = await controller.install(widget.file, name: name);
    if (!mounted) return;
    setState(() => _installing = false);
    final text = result == null
        ? (controller.problem ?? 'Your watch could not be reached.')
        : result.success
        ? '$name is on your watch.'
        : 'Your watch refused it: ${result.message ?? result.code ?? 'no reason given'}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    if (result?.success ?? false) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    final info = _info;
    final fileName = widget.file.uri.pathSegments.last;
    if (info == null) {
      return TabPage(
        title: fileName,
        slivers: [
          SliverToBoxAdapter(
            child: _error == null
                ? const Padding(
                    padding: EdgeInsets.all(Space.section),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                : EmptyState(title: 'Not a watch package', message: '$_error The watch installs .tpk and .wgt files.'),
          ),
        ],
      );
    }
    final name = info.displayName ?? info.packageId;
    final face = info.kind == PackageKind.watchFace;
    final onWatch = c.packages.where((p) => p.id == info.packageId).firstOrNull;
    final running = _installing ? c.operation : null;
    final width = MediaQuery.sizeOf(context).width;
    final doubtful = _verdict != SignatureVerdict.storeSigned && _verdict != SignatureVerdict.unknown;
    final icon = _pictures.isEmpty ? null : _pictures.first;
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
                          DiscFace(id: info.packageId, name: name, picture: icon == null ? null : MemoryImage(icon)),
                        ],
                        onTap: _pictures.isEmpty ? null : () => showPictures(context, _pictures, title: name),
                        progress: running?.progress,
                        turns: c.presentations,
                      ),
                    )
                  : GestureDetector(
                      onTap: _pictures.isEmpty ? null : () => showPictures(context, _pictures, title: name),
                      child: PackagePicture(name: name, bytes: icon, round: false, size: 128, ring: Palette.line),
                    ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.screen),
          sliver: SliverList.list(
            children: [
              SpecRow('Kind', face ? 'Watch face' : 'App'),
              SpecRow('Package', info.packageId),
              if (info.version != null) SpecRow('Version', info.version!),
              if (onWatch != null) SpecRow('On your watch', 'Version ${onWatch.version}'),
              SpecRow('Signature', _verdictText(_verdict), risk: doubtful),
              const SizedBox(height: Space.xxl),
              if (running != null)
                JobProgress(label: running.label, progress: running.progress, ticks: !face)
              else
                AppButton(
                  label: onWatch == null ? 'Install on my watch' : 'Install over version ${onWatch.version}',
                  expand: true,
                  onPressed: c.phase == LinkPhase.connected && c.operation == null ? () => _install(name) : null,
                ),
              if (doubtful) ...[
                const SizedBox(height: Space.m),
                Text(
                  'Your watch will likely refuse it. It decides when you install.',
                  style: AppType.caption.copyWith(color: Palette.alert),
                ),
              ],
              if (c.phase != LinkPhase.connected && running == null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Text(
                    'Connect your watch on the Watch tab to install.',
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

  static String _verdictText(SignatureVerdict? v) => switch (v) {
    SignatureVerdict.storeSigned => 'Signed for the store',
    SignatureVerdict.deviceBound => 'For a few specific watches',
    SignatureVerdict.expired => 'Certificate expired',
    SignatureVerdict.untrusted => 'Not signed by the store',
    SignatureVerdict.unsigned => 'Not signed',
    SignatureVerdict.unknown || null => 'Could not be checked',
  };
}
