import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_style.dart';

/// App 主題(Material 3,現代精緻風,支援淺/深色)。
class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF6366F1); // 靛藍

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final base = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    // 微調表面色調,追求乾淨、有層次的質感。
    final scheme = isDark
        ? base.copyWith(
            surface: const Color(0xFF0C0E14),
            surfaceContainerLowest: const Color(0xFF0A0B10),
            surfaceContainerLow: const Color(0xFF12141C),
            surfaceContainer: const Color(0xFF161923),
            surfaceContainerHigh: const Color(0xFF1C2029),
            surfaceContainerHighest: const Color(0xFF232735),
            primary: const Color(0xFFA5B4FC),
            onSurface: const Color(0xFFE8EAF2),
          )
        : base.copyWith(
            surface: const Color(0xFFFBFBFE),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF6F6FC),
            surfaceContainer: const Color(0xFFF1F1FA),
            surfaceContainerHigh: const Color(0xFFECECF7),
            surfaceContainerHighest: const Color(0xFFE6E6F3),
          );

    final textColor = scheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(textColor),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: textColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyle.rLg)),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.6),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHigh.withValues(alpha: 0.6)
            : scheme.surfaceContainer,
        hintStyle: TextStyle(color: scheme.outline),
        prefixIconColor: scheme.outline,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyle.rMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyle.rMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyle.rMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppStyle.rMd)),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyle.rXl)),
        backgroundColor: scheme.surfaceContainer,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyle.rSm)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppStyle.rXl)),
        ),
      ),
    );
  }

  static TextTheme _textTheme(Color color) {
    return TextTheme(
      displaySmall: TextStyle(
          color: color, fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineMedium: TextStyle(
          color: color, fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineSmall: TextStyle(
          color: color, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: TextStyle(
          color: color, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: TextStyle(
          color: color, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      bodyLarge: TextStyle(color: color, height: 1.5),
      bodyMedium: TextStyle(color: color, height: 1.5),
    );
  }
}
