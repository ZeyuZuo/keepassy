import 'package:flutter/material.dart';

const _seed = Color(0xFF19745B);
const _surface = Color(0xFFF6F4EF);
const _panel = Color(0xFFFCFBF7);
const _ink = Color(0xFF20231F);

ThemeData buildKeepassYTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.light,
    surface: _surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: _seed,
      onPrimary: Colors.white,
      surface: _surface,
      surfaceContainerLowest: _panel,
      surfaceContainerLow: const Color(0xFFF0EEE7),
      outlineVariant: const Color(0xFFD8D4C9),
    ),
    scaffoldBackgroundColor: _surface,
    fontFamily: 'Roboto',
    textTheme: Typography.blackMountainView.apply(
      bodyColor: _ink,
      displayColor: _ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _panel,
      foregroundColor: _ink,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD8D4C9)),
      ),
      filled: true,
      fillColor: _panel,
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
    dividerTheme: const DividerThemeData(
      color: Color(0xFFD8D4C9),
      space: 1,
      thickness: 1,
    ),
  );
}
