import 'package:flutter/material.dart';

const _seed = Color(0xFF19745B);

// Light
const _lightSurface = Color(0xFFF6F4EF);
const _lightPanel = Color(0xFFFCFBF7);
const _lightInk = Color(0xFF20231F);
const _lightSurfaceLow = Color(0xFFF0EEE7);
const _lightOutline = Color(0xFFD8D4C9);

// Dark
const _darkSurface = Color(0xFF1A1D1A);
const _darkPanel = Color(0xFF222622);
const _darkInk = Color(0xFFE3E3DD);
const _darkSurfaceLow = Color(0xFF252825);
const _darkOutline = Color(0xFF44483F);

ThemeData buildKeepassYTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final ink = isDark ? _darkInk : _lightInk;
  final surface = isDark ? _darkSurface : _lightSurface;

  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    surface: surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: isDark ? const Color(0xFF43A684) : _seed,
      onPrimary: isDark ? const Color(0xFF003825) : Colors.white,
      surface: surface,
      surfaceContainerLowest: isDark ? _darkPanel : _lightPanel,
      surfaceContainerLow: isDark ? _darkSurfaceLow : _lightSurfaceLow,
      outlineVariant: isDark ? _darkOutline : _lightOutline,
    ),
    scaffoldBackgroundColor: surface,
    fontFamily: 'Roboto',
    textTheme: ThemeData(brightness: brightness)
        .textTheme
        .apply(bodyColor: ink, displayColor: ink),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? _darkPanel : _lightPanel,
      foregroundColor: ink,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
            color: isDark ? _darkOutline : _lightOutline),
      ),
      filled: true,
      fillColor: isDark ? _darkPanel : _lightPanel,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(40, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? _darkOutline : _lightOutline,
      space: 1,
      thickness: 1,
    ),
  );
}
