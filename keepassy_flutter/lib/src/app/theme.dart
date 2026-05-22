import 'package:flutter/material.dart';

enum KeepassYAccent {
  green('green', 'Green', Color(0xFF1B7356)),
  teal('teal', 'Teal', Color(0xFF006A6A)),
  blue('blue', 'Blue', Color(0xFF2865B5)),
  violet('violet', 'Violet', Color(0xFF6954C8)),
  amber('amber', 'Amber', Color(0xFF8A6100)),
  rose('rose', 'Rose', Color(0xFFB13D61));

  const KeepassYAccent(this.id, this.label, this.seed);

  final String id;
  final String label;
  final Color seed;

  static KeepassYAccent fromId(String id) {
    for (final accent in values) {
      if (accent.id == id) return accent;
    }
    return KeepassYAccent.green;
  }
}

class KeepassYMotion {
  const KeepassYMotion._();

  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}

class KeepassYRadius {
  const KeepassYRadius._();

  static const compact = 12.0;
  static const control = 16.0;
  static const panel = 24.0;
  static const dialog = 28.0;
}

class KeepassYSpacing {
  const KeepassYSpacing._();

  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class KeepassYVaultColors extends ThemeExtension<KeepassYVaultColors> {
  const KeepassYVaultColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  @override
  KeepassYVaultColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) {
    return KeepassYVaultColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    );
  }

  @override
  KeepassYVaultColors lerp(
    ThemeExtension<KeepassYVaultColors>? other,
    double t,
  ) {
    if (other is! KeepassYVaultColors) return this;
    return KeepassYVaultColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
    );
  }
}

const _lightSurface = Color(0xFFFAF9F6);
const _lightSurfaceLow = Color(0xFFF3F0EA);
const _lightPanel = Color(0xFFFFFCF7);
const _lightInk = Color(0xFF1B1C19);

const _darkSurface = Color(0xFF111412);
const _darkSurfaceLow = Color(0xFF1B1F1C);
const _darkPanel = Color(0xFF202520);
const _darkInk = Color(0xFFE4E4DE);

ThemeData buildKeepassYTheme({
  Brightness brightness = Brightness.light,
  String accentId = 'green',
}) {
  final isDark = brightness == Brightness.dark;
  final ink = isDark ? _darkInk : _lightInk;
  final surface = isDark ? _darkSurface : _lightSurface;
  final panel = isDark ? _darkPanel : _lightPanel;
  final surfaceLow = isDark ? _darkSurfaceLow : _lightSurfaceLow;
  final accent = KeepassYAccent.fromId(accentId);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent.seed,
    brightness: brightness,
    surface: surface,
  );
  final colorScheme = scheme.copyWith(
    primary: isDark ? scheme.primaryContainer : scheme.primary,
    onPrimary: isDark ? scheme.onPrimaryContainer : scheme.onPrimary,
    surface: surface,
    surfaceContainerLowest: panel,
    surfaceContainerLow: surfaceLow,
    surfaceContainer: isDark
        ? const Color(0xFF222721)
        : const Color(0xFFF7F3ED),
    surfaceContainerHigh: isDark
        ? const Color(0xFF282E28)
        : const Color(0xFFF0ECE5),
    surfaceContainerHighest: isDark
        ? const Color(0xFF313731)
        : const Color(0xFFE9E4DC),
    outlineVariant: isDark ? const Color(0xFF485047) : const Color(0xFFD8D2C7),
  );

  final borderRadius = BorderRadius.circular(KeepassYRadius.control);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: surface,
    fontFamily: 'Roboto',
    textTheme: ThemeData(
      brightness: brightness,
    ).textTheme.apply(bodyColor: ink, displayColor: ink),
    appBarTheme: AppBarTheme(
      backgroundColor: panel,
      foregroundColor: ink,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
      filled: true,
      fillColor: panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        side: BorderSide(color: colorScheme.outlineVariant),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KeepassYRadius.compact),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: isDark ? 0 : 1,
      surfaceTintColor: colorScheme.surfaceTint,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KeepassYRadius.panel),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KeepassYRadius.compact),
      ),
      side: BorderSide(color: colorScheme.outlineVariant),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KeepassYRadius.dialog),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: panel,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KeepassYRadius.control),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KeepassYRadius.control),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: borderRadius),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Icon(Icons.check, size: 16);
        }
        return null;
      }),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    extensions: [
      KeepassYVaultColors(
        success: isDark ? const Color(0xFF7CD8A5) : const Color(0xFF146C43),
        onSuccess: isDark ? const Color(0xFF00391D) : Colors.white,
        successContainer: isDark
            ? const Color(0xFF0D4D2B)
            : const Color(0xFFD7F6DF),
        onSuccessContainer: isDark
            ? const Color(0xFFC2F0D0)
            : const Color(0xFF00210E),
        warning: isDark ? const Color(0xFFE6C26C) : const Color(0xFF765A00),
        onWarning: isDark ? const Color(0xFF3F2E00) : Colors.white,
        warningContainer: isDark
            ? const Color(0xFF584400)
            : const Color(0xFFFFE7A8),
        onWarningContainer: isDark
            ? const Color(0xFFFFE7A8)
            : const Color(0xFF241A00),
      ),
    ],
  );
}
