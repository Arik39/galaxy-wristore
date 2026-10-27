import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/api.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/page.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../common/pictures.dart';
import 'file_package_page.dart';
import 'package_page.dart';

/// Tizen Archive, the store that replaces the closed Galaxy Store: faces and apps to search, look at and install.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  CatalogKind _kind = CatalogKind.watchFace;
  final List<CatalogEntry> _items = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 1;
      }
    });
    try {
      final page = await WatchScope.read(context).services.catalog
          .search(query: _search.text, kind: _kind, page: _page);
      if (!mounted || request != _request) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _page = page.page + 1;
      });
    } on CatalogException catch (e) {
      if (mounted && request == _request) setState(() => _error = 'Tizen Archive did not answer: ${e.message}');
    } on Exception {
      if (mounted && request == _request) {
        setState(() => _error = 'Tizen Archive could not be reached. Check the internet connection.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final c = WatchScope.of(context);
    final installed = {for (final p in c.packages) p.id};
    final faces = _kind == CatalogKind.watchFace;
    return TabPage(
      title: 'Discover',
      onRefresh: () => _load(reset: true),
      actions: [
        IconButton(
          tooltip: 'Install a package file',
          onPressed: () => pickPackageFile(context),
          icon: const AppIconView(AppIcon.fileIn, color: Palette.ink),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.screen, Space.xs, Space.screen, Space.xl),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: _onQuery,
                  textInputAction: TextInputAction.search,
                  style: AppType.body,
                  decoration: const InputDecoration(
                    hintText: 'Search Tizen Archive',
                    prefixIcon: Padding(
                      padding: EdgeInsets.all(12),
                      child: AppIconView(AppIcon.search, color: Palette.inkSoft, size: 20),
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: Space.m),
                BarScale(
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<CatalogKind>(
                      segments: const [
                        ButtonSegment(value: CatalogKind.watchFace, label: Text('FACES')),
                        ButtonSegment(value: CatalogKind.app, label: Text('APPS')),
                      ],
                      selected: {_kind},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        setState(() => _kind = s.first);
                        _load(reset: true);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null && _items.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              title: 'Nothing to show',
              message: _error!,
              action: AppButton(label: 'Try again', onPressed: () => _load(reset: true)),
            ),
          )
        else if (!_loading && _items.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              title: 'No ${faces ? 'faces' : 'apps'} found',
              message: 'Tizen Archive has nothing that matches "${_search.text}". Try another word.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Space.screen),
            sliver: PictureGrid(
              maxTile: 128,
              lines: const [AppType.caption, AppType.caption, AppType.label],
              gap: Space.s + 2,
              itemCount: _items.length,
              itemBuilder: (context, i) {
                if (i == _items.length - 4 && _hasMore && !_loading) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: false));
                }
                return _EntryTile(entry: _items[i], round: faces, installed: installed.contains(_items[i].id));
              },
            ),
          ),
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(Space.xxl),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.round, required this.installed});

  final CatalogEntry entry;
  final bool round;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${entry.name}${installed ? ', on your watch' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PackagePage(entry: entry))),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) =>
                  CatalogIcon(entry: entry, round: round, size: constraints.maxWidth, ring: Palette.lineFaint),
            ),
            const SizedBox(height: Space.s),
            Text(
              entry.name,
              style: AppType.caption.copyWith(color: Palette.ink),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            if (installed) ...[
              const SizedBox(height: 2),
              const Text('ON WATCH', style: AppType.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loads a catalog icon once from Tizen Archive and keeps it for the session.
Future<Uint8List?> catalogIcon(BuildContext context, String? path) async {
  if (path == null) return null;
  final cached = _icons[path];
  if (cached != null) return cached;
  try {
    return _icons[path] = await WatchScope.read(context).services.catalog.icon(path);
  } on Exception {
    return null;
  }
}

final _icons = <String, Uint8List>{};

/// A catalog entry's icon; for a face, a preview of the whole face.
class CatalogIcon extends StatefulWidget {
  const CatalogIcon({super.key, required this.entry, required this.round, required this.size, this.ring});

  final CatalogEntry entry;
  final bool round;
  final double size;
  final Color? ring;

  @override
  State<CatalogIcon> createState() => _CatalogIconState();
}

class _CatalogIconState extends State<CatalogIcon> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _icons[widget.entry.iconPath];
    if (_bytes == null) {
      catalogIcon(context, widget.entry.iconPath).then((bytes) {
        if (mounted && bytes != null) setState(() => _bytes = bytes);
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      PackagePicture(name: widget.entry.name, bytes: _bytes, round: widget.round, size: widget.size, ring: widget.ring);
}
