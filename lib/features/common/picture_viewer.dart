import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';

/// Opens pictures full screen on black: swipe between them, pinch or double-tap to zoom, drag to move.
Future<void> showPictures(BuildContext context, List<Uint8List> pictures, {int start = 0, String? title}) =>
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: Motion.medium,
        reverseTransitionDuration: Motion.short,
        pageBuilder: (_, _, _) => _Viewer(pictures: pictures, start: start, title: title),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Motion.ease),
          child: child,
        ),
      ),
    );

class _Viewer extends StatefulWidget {
  const _Viewer({required this.pictures, required this.start, this.title});

  final List<Uint8List> pictures;
  final int start;
  final String? title;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final _pages = PageController(initialPage: widget.start);
  late int _index = widget.start;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            itemCount: widget.pictures.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _ZoomablePicture(
              bytes: widget.pictures[i],
              onZoomChanged: (z) {
                if (z != _zoomed) setState(() => _zoomed = z);
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const AppIconView(AppIcon.close, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      widget.title ?? '',
                      style: AppType.bodyStrong,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      widget.pictures.length > 1 ? '${_index + 1} / ${widget.pictures.length}' : '',
                      style: AppType.caption.copyWith(
                        color: Colors.white70,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomablePicture extends StatefulWidget {
  const _ZoomablePicture({required this.bytes, required this.onZoomChanged});

  final Uint8List bytes;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePicture> createState() => _ZoomablePictureState();
}

class _ZoomablePictureState extends State<_ZoomablePicture> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _animation = AnimationController(vsync: this, duration: Motion.short);
  Animation<Matrix4>? _tween;
  TapDownDetails? _doubleTap;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() => widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01));
    _animation.addListener(() {
      if (_tween != null) _transform.value = _tween!.value;
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    _animation.dispose();
    super.dispose();
  }

  /// Double-tap: zoom in where the finger is, or back out to the whole picture.
  void _toggleZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 end;
    if (zoomed) {
      end = Matrix4.identity();
    } else {
      final at = _doubleTap?.localPosition ?? Offset.zero;
      const scale = 2.6;
      end = Matrix4.identity()
        ..translateByDouble(-at.dx * (scale - 1), -at.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
    _tween = Matrix4Tween(
      begin: _transform.value,
      end: end,
    ).animate(CurvedAnimation(parent: _animation, curve: Motion.ease));
    _animation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTap = d,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        maxScale: 8,
        child: Center(
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (context, _, _) => Text('This picture cannot be shown.', style: AppType.secondary),
          ),
        ),
      ),
    );
  }
}
