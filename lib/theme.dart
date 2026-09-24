import 'package:flutter/material.dart';

/// The F1 Pulse colours: racing red on carbon black, with white text.
/// Every screen gets these from the theme, so changing a colour here
/// changes it everywhere.
class F1Colors {
  static const Color red = Color(0xFFE10600);
  static const Color carbon = Color(0xFF15151E); // the background
  static const Color surface = Color(0xFF1F1F27); // cards
  static const Color surfaceHigh = Color(0xFF2B2B36); // chips, dialogs
  static const Color muted = Color(0xFFA0A0AB); // secondary text
}

/// The font. Titillium Web is free (SIL Open Font License) and has the
/// wide, technical look of motorsport graphics. The files are in
/// assets/fonts and listed in pubspec.yaml.
const String appFont = 'TitilliumWeb';

ThemeData buildF1Theme() {
  // Start from a generated dark scheme, then pin the colours that matter.
  final scheme = ColorScheme.fromSeed(
    seedColor: F1Colors.red,
    brightness: Brightness.dark,
  ).copyWith(
    primary: F1Colors.red,
    onPrimary: Colors.white,
    secondaryContainer: F1Colors.red, // the pill behind the selected tab
    onSecondaryContainer: Colors.white,
    surface: F1Colors.carbon,
    onSurface: Colors.white,
    onSurfaceVariant: F1Colors.muted,
    surfaceContainerLow: F1Colors.surface,
    surfaceContainer: F1Colors.surface,
    surfaceContainerHigh: F1Colors.surfaceHigh,
    surfaceContainerHighest: F1Colors.surfaceHigh,
    outlineVariant: Colors.white12,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: F1Colors.carbon,
    fontFamily: appFont,
    appBarTheme: const AppBarTheme(
      backgroundColor: F1Colors.carbon,
      foregroundColor: Colors.white,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: appFont,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: F1Colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: Colors.white12),
  );
}
