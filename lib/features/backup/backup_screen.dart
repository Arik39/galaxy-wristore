import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app.dart';
import '../../app/watch_controller.dart';
import '../../design/controls.dart';
import '../../design/format.dart';
import '../../design/icons.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';
import 'restore_page.dart';

/// Galaxy Wristore's own backup, in place of Samsung's: one file per backup, kept on the phone and shareable.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    return TabPage(
      title: 'Backup',
      actions: [
        IconButton(
          tooltip: 'Add a backup file',
          onPressed: () => _import(context, c),
          icon: const AppIconView(AppIcon.fileIn, color: Palette.ink),
        ),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.screen),
          sliver: SliverToBoxAdapter(child: _Now(controller: c)),
        ),
        if (c.backups.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader('Your backups', onInfo: () => _explain(context), infoLabel: 'What a backup holds'),
          ),
          SliverList.builder(
            itemCount: c.backups.length,
            itemBuilder: (context, i) => _BackupRow(record: c.backups[i], controller: c),
          ),
        ],
      ],
    );
  }

  static const _limits =
      'A backup cannot hold what the watch keeps locked: the data inside its apps, and its settings. Everything else a '
      'reset erases is in it.';

  Future<void> _explain(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What a backup holds', style: AppType.title),
            const SizedBox(height: Space.m),
            Text(
              'Copies of the faces and apps you added that Tizen Archive has; the music and pictures on the watch; and a '
              'fingerprint of every app.',
              style: AppType.body,
            ),
            const SizedBox(height: Space.m),
            Text(Disclaimer.text, style: AppType.body.copyWith(color: Palette.inkSoft)),
            const SizedBox(height: Space.m),
            Text(_limits, style: AppType.body.copyWith(color: Palette.inkSoft)),
          ],
        ),
      ),
    ),
  );

  Future<void> _import(BuildContext context, WatchController c) async {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Choose a watch backup');
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.twbackup')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('That is not a watch backup. Its name ends in .twbackup.')));
      }
      return;
    }
    final folder = await WatchController.backupFolder();
    final name = File(path).uri.pathSegments.last;
    await File(path).copy('${folder.path}/$name');
    await c.loadBackups();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name is added to your backups.')));
    }
  }
}

/// The state of things now: when the last backup was, what is not in it, and the button.
class _Now extends StatelessWidget {
  const _Now({required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final latest = c.latestBackup;
    final unsaved = c.notBackedUp;
    final notYet = c.toBackUp;
    final never = c.unsaveable;
    final running = c.job == Job.backingUp ? c.operation : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (latest == null) ...[
          Text('No backup yet', style: AppType.title),
          const SizedBox(height: Space.s),
          Text(
            'A backup keeps copies of the faces and apps you added, and the music and pictures on the watch.',
            style: AppType.secondary,
          ),
        ] else ...[
          SpecRow('Last backup', formatWhen(latest.createdAt)),
          SpecRow(
            'Faces and apps',
            c.packages.isEmpty ? '${latest.idsWithCopy.length}' : '${c.backedUpCount} of ${c.downloaded.length}',
            risk: unsaved.isNotEmpty,
          ),
          SpecRow('Files', '${latest.mediaCount}'),
          if (notYet.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            _RiskLine('Not in it yet: ${listNames([for (final p in notYet) p.name], max: 3)}'),
          ],
          if (never.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            _RiskLine(
              'Tizen Archive does not have ${listNames([for (final p in never) p.name], max: 3)}, so no backup can '
              'save ${never.length == 1 ? 'it' : 'them'}.',
            ),
          ],
        ],
        const SizedBox(height: Space.xxl),
        AnimatedSwitcher(
          duration: Motion.short,
          child: running != null
              ? Column(
                  key: const ValueKey('running'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    JobProgress(label: running.label, progress: running.progress),
                    const SizedBox(height: Space.m),
                    AppButton(
                      label: c.stopping ? 'Stopping' : 'Stop',
                      filled: false,
                      expand: true,
                      onPressed: c.stopping ? null : c.stopBackUp,
                    ),
                  ],
                )
              : AppButton(
                  key: const ValueKey('button'),
                  label: 'Back up now',
                  expand: true,
                  onPressed: c.phase == LinkPhase.connected && c.operation == null ? () => _backUp(context) : null,
                ),
        ),
        if (c.phase != LinkPhase.connected && running == null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              'Connect your watch on the Watch tab to back it up.',
              style: AppType.caption,
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: Space.l),
        const Disclaimer(),
      ],
    );
  }

  Future<void> _backUp(BuildContext context) async {
    final file = await controller.backUp();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          file != null
              ? 'Backed up: ${file.uri.pathSegments.last}'
              : controller.wasStopped
              ? 'The backup is stopped. Nothing of it was kept.'
              : (controller.problem ?? 'The backup did not finish.'),
        ),
      ),
    );
  }
}

/// Something a reset would remove for good, with the red dot.
class _RiskLine extends StatelessWidget {
  const _RiskLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 5), child: RiskDot()),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(text, style: AppType.secondary.copyWith(color: Palette.ink)),
        ),
      ],
    );
  }
}

/// What a backup can and cannot bring back, said where a backup is made.
class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});

  static const text =
      'A backup can bring back only the faces and apps that Tizen Archive has. An installed app cannot be copied off '
      'the watch, so one the archive does not have is not in your backup.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: AppIconView(AppIcon.info, color: Palette.inkSoft, size: 16),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(text, style: AppType.caption.copyWith(color: Palette.inkSoft)),
          ),
        ],
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({required this.record, required this.controller});

  final BackupRecord record;
  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final file = record.file;
    final demo = controller.services.demo;
    final what =
        '${count(record.idsWithCopy.length, 'face or app', 'faces and apps')} · ${count(record.mediaCount, 'file')}';
    return InkWell(
      onTap: file == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RestorePage(record: record))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.screen, Space.m, Space.s, Space.m),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatWhen(record.createdAt), style: AppType.body),
                  const SizedBox(height: 3),
                  Text(demo ? '$what · demo' : what, style: AppType.caption),
                ],
              ),
            ),
            if (file != null && !demo)
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const AppIconView(AppIcon.chevronDown, color: Palette.inkSoft, size: 20),
                onSelected: (action) => switch (action) {
                  'restore' => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => RestorePage(record: record))),
                  'share' => SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Watch backup')),
                  _ => _delete(context, file),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'restore', child: Text('Restore from it')),
                  PopupMenuItem(value: 'share', child: Text('Save or share the file')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Palette.alert)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, File file) async {
    final sure = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialog) => AlertDialog(
        title: Text('Delete this backup?', style: AppType.title),
        content: Text(
          'The backup of ${formatWhen(record.createdAt).toLowerCase()} is removed from this phone. Copies you saved elsewhere stay.',
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
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    if (file.existsSync()) file.deleteSync();
    await controller.loadBackups();
  }
}
