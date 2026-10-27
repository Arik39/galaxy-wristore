import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/type.dart';

/// The app's Material theme: near-black, ink white, red for what is at risk. Dark by design. Page transitions follow
/// each platform (a push with edge-swipe back on iOS, predictive back on Android).
ThemeData buildTheme() {
  final scheme = const ColorScheme.dark().copyWith(
    primary: Palette.ink,
    onPrimary: Palette.void_,
    primaryContainer: Palette.graphiteHigh,
    onPrimaryContainer: Palette.ink,
    secondary: Palette.inkSoft,
    onSecondary: Palette.void_,
    surface: Palette.void_,
    onSurface: Palette.ink,
    onSurfaceVariant: Palette.inkSoft,
    surfaceContainerLowest: Palette.void_,
    surfaceContainerLow: Palette.graphite,
    surfaceContainer: Palette.graphite,
    surfaceContainerHigh: Palette.graphiteHigh,
    surfaceContainerHighest: Palette.graphiteHigh,
    outline: Palette.line,
    outlineVariant: Palette.lineFaint,
    error: Palette.alert,
    onError: Palette.void_,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Palette.void_,
    textTheme: base.textTheme.apply(bodyColor: Palette.ink, displayColor: Palette.ink),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Palette.ink,
      selectionColor: Palette.ink.withValues(alpha: 0.25),
      selectionHandleColor: Palette.ink,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Palette.ink,
      titleTextStyle: AppType.name.copyWith(fontSize: 16),
      centerTitle: true,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Palette.void_,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      height: 64,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.graphiteHigh,
      contentTextStyle: AppType.body,
      actionTextColor: Palette.ink,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radii.panel),
        side: BorderSide(color: Palette.line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.graphite,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Palette.inkFaint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radii.panel)),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Palette.graphite,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radii.panel),
        side: BorderSide(color: Palette.line),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Palette.graphiteHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radii.panel),
        side: BorderSide(color: Palette.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.graphite,
      hintStyle: AppType.body.copyWith(color: Palette.inkFaint),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radii.control),
        borderSide: BorderSide(color: Palette.line),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radii.control),
        borderSide: BorderSide(color: Palette.line),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radii.control),
        borderSide: BorderSide(color: Palette.ink),
      ),
    ),
    // The chosen segment is lit graphite, not white: white is kept for a screen's one primary button.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Palette.graphiteHigh,
        selectedForegroundColor: Palette.ink,
        foregroundColor: Palette.inkSoft,
        side: const BorderSide(color: Palette.line),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.control)),
        textStyle: AppType.button,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.ink : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Palette.void_),
      side: const BorderSide(color: Palette.inkFaint, width: 1.5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Palette.ink, linearTrackColor: Palette.lineFaint),
    dividerTheme: const DividerThemeData(color: Palette.line, thickness: 1, space: 1),
  );
}
