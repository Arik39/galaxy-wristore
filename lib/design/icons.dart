import 'package:flutter/material.dart';

/// The app's own line icons: one 24-unit grid, one 1.7 stroke, round caps and joins.
enum AppIcon {
  watch,
  faces,
  apps,
  discover,
  backup,
  restore,
  settings,
  search,
  chevronRight,
  chevronLeft,
  chevronDown,
  close,
  check,
  alert,
  wifi,
  battery,
  storage,
  refresh,
  plus,
  download,
  trash,
  info,

  /// A file coming in: adding a backup file or a package file.
  fileIn,
}

class AppIconView extends StatelessWidget {
  const AppIconView(this.icon, {super.key, this.size = 24, this.color, this.strokeWidth = 1.7, this.semanticLabel});

  final AppIcon icon;
  final double size;
  final Color? color;
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      size: Size.square(size),
      painter: _IconPainter(icon, color ?? IconTheme.of(context).color ?? Colors.white, strokeWidth),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: paint)
        : Semantics(label: semanticLabel, image: true, child: paint);
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.strokeWidth);

  final AppIcon icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_path(icon), paint);
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}

Path _circle(double cx, double cy, double r) => Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));

Path _rrect(double x, double y, double w, double h, double r) =>
    Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)));

Path _poly(List<double> xy, {bool close = false}) {
  final path = Path()..moveTo(xy[0], xy[1]);
  for (var i = 2; i < xy.length; i += 2) {
    path.lineTo(xy[i], xy[i + 1]);
  }
  if (close) path.close();
  return path;
}

Path _arc(double x0, double y0, double r, double x1, double y1, {bool large = false, bool clockwise = true}) => Path()
  ..moveTo(x0, y0)
  ..arcToPoint(Offset(x1, y1), radius: Radius.circular(r), largeArc: large, clockwise: clockwise);

Path _all(List<Path> parts) {
  final path = Path();
  for (final part in parts) {
    path.addPath(part, Offset.zero);
  }
  return path;
}

Path _tray() => _all([
  _poly([4, 14, 4, 18.5]),
  _arc(4, 18.5, 1.5, 5.5, 20, clockwise: false),
  _poly([5.5, 20, 18.5, 20]),
  _arc(18.5, 20, 1.5, 20, 18.5, clockwise: false),
  _poly([20, 18.5, 20, 14]),
]);

Path _path(AppIcon icon) => switch (icon) {
  AppIcon.watch => _all([
    _circle(12, 12, 6.5),
    _poly([9, 5.8, 9.6, 2, 14.4, 2, 15, 5.8]),
    _poly([9, 18.2, 9.6, 22, 14.4, 22, 15, 18.2]),
    _poly([12, 9.5, 12, 12, 13.8, 13.2]),
  ]),
  // One dial, no strap: the four quarter ticks and two hands at 10:08.
  AppIcon.faces => _all([
    _circle(12, 12, 9),
    _poly([12, 4.6, 12, 6.2]),
    _poly([19.4, 12, 17.8, 12]),
    _poly([12, 19.4, 12, 17.8]),
    _poly([4.6, 12, 6.2, 12]),
    _poly([8.9, 9.9, 12, 12, 16.1, 8.3]),
  ]),
  AppIcon.apps => _all([
    _rrect(3.5, 3.5, 7, 7, 2),
    _rrect(13.5, 3.5, 7, 7, 2),
    _rrect(3.5, 13.5, 7, 7, 2),
    _rrect(13.5, 13.5, 7, 7, 2),
  ]),
  AppIcon.discover => _all([
    _circle(12, 12, 9),
    _poly([15.5, 8.5, 13.5, 13.5, 8.5, 15.5, 10.5, 10.5], close: true),
  ]),
  AppIcon.backup => _all([
    _tray(),
    _poly([12, 4, 12, 14]),
    _poly([8, 10, 12, 14, 16, 10]),
  ]),
  AppIcon.restore => _all([
    _tray(),
    _poly([12, 14, 12, 4]),
    _poly([8, 8, 12, 4, 16, 8]),
  ]),
  AppIcon.settings => _all([
    _poly([4, 7.5, 20, 7.5]),
    _circle(9, 7.5, 2.3),
    _poly([4, 16.5, 20, 16.5]),
    _circle(15, 16.5, 2.3),
  ]),
  AppIcon.search => _all([
    _circle(11, 11, 6.5),
    _poly([20, 20, 15.8, 15.8]),
  ]),
  AppIcon.chevronRight => _poly([9, 6, 15, 12, 9, 18]),
  AppIcon.chevronLeft => _poly([15, 6, 9, 12, 15, 18]),
  AppIcon.chevronDown => _poly([6, 9, 12, 15, 18, 9]),
  AppIcon.close => _all([
    _poly([6, 6, 18, 18]),
    _poly([18, 6, 6, 18]),
  ]),
  AppIcon.check => _poly([5, 12.5, 10, 17.5, 19, 7]),
  AppIcon.alert => _all([
    _circle(12, 12, 9),
    _poly([12, 7.5, 12, 13]),
    _poly([12, 16.3, 12, 16.6]),
  ]),
  AppIcon.wifi => _all([
    _arc(3.5, 9.5, 12, 20.5, 9.5),
    _arc(6.5, 12.8, 7.8, 17.5, 12.8),
    _arc(9.5, 16, 3.6, 14.5, 16),
    _poly([12, 19.2, 12, 19.4]),
  ]),
  AppIcon.battery => _all([
    _rrect(2.5, 7.5, 17, 9, 2.2),
    _poly([21.5, 10.8, 21.5, 13.2]),
  ]),
  AppIcon.storage => _all([
    _rrect(3, 6.5, 18, 11, 2.5),
    _poly([3, 13, 21, 13]),
    _poly([17, 15.3, 17, 15.5]),
  ]),
  AppIcon.refresh => _all([
    _arc(19.5, 12, 7.5, 16.9, 6.2, large: true),
    _poly([19.5, 3.5, 19.5, 7.8, 15.2, 7.8]),
  ]),
  AppIcon.plus => _all([
    _poly([12, 5, 12, 19]),
    _poly([5, 12, 19, 12]),
  ]),
  AppIcon.download => _all([
    _poly([12, 4, 12, 15]),
    _poly([7.5, 10.5, 12, 15, 16.5, 10.5]),
    _poly([5, 20, 19, 20]),
  ]),
  AppIcon.trash => _all([
    _poly([4.5, 7, 19.5, 7]),
    _poly([9.5, 7, 9.5, 4.5, 14.5, 4.5, 14.5, 7]),
    _poly([6.5, 7, 7.5, 20, 16.5, 20, 17.5, 7]),
  ]),
  AppIcon.info => _all([
    _circle(12, 12, 9),
    _poly([12, 11, 12, 16.5]),
    _poly([12, 7.6, 12, 7.8]),
  ]),
  AppIcon.fileIn => _all([
    _poly([13.5, 3, 6, 3, 6, 21, 18, 21, 18, 7.5, 13.5, 3]),
    _poly([13.5, 3, 13.5, 7.5, 18, 7.5]),
    _poly([12, 10, 12, 17]),
    _poly([9, 14, 12, 17, 15, 14]),
  ]),
};
