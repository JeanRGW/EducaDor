import 'package:flutter/material.dart';

/// Design tokens extracted from the Figma mockups.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFF036FA9);
  static const primaryDark = Color(0xFF025887);
  static const navy = Color(0xFF0B3B4A);
  static const navyDeep = Color(0xFF082D38);

  // Surfaces
  static const background = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);

  // Text
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);

  // Semantic
  static const success = Color(0xFF10B981);
  static const successBright = Color(0xFF23D3B4);
  static const successBg = Color(0xFFCCFBF1);
  static const successBgSoft = Color(0xFFF0FDF4);
  static const activeBg = Color(0xFFD1FAE5);
  static const successDarkGreen = Color(0xFF0D9488);
  static const warning = Color(0xFFF59E0B);
  static const warningBg = Color(0xFFFFFBEB);
  static const danger = Color(0xFFEF4444);
  static const dangerBg = Color(0xFFFEE2E2);
  static const chipBg = Color(0xFFF1F5F9);

  // Auth gradient (splash / welcome / role select)
  static const authGradientTop = Color(0xFF0386BF);
  static const authGradientBottom = Color(0xFF0C938C);

  // Chart palette
  static const chartBlue = Color(0xFF036FA9);
  static const accentTeal = Color(0xFF0D9488);
  static const gradientEnd = Color(0xFF13A0B7);
}

/// Font families vendored from Google Fonts (OFL) to match the prototypes:
/// Outfit for display/headings/numbers, Inter for body/UI text.
class AppFonts {
  AppFonts._();

  static const outfit = 'Outfit';
  static const inter = 'Inter';
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      fontFamily: AppFonts.inter,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFE0F2FE),
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.successDarkGreen,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.successBg,
        onSecondaryContainer: AppColors.successDarkGreen,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        surfaceContainerLowest: AppColors.surface,
        surfaceContainerLow: AppColors.background,
        surfaceContainer: AppColors.chipBg,
        surfaceContainerHigh: AppColors.chipBg,
        surfaceContainerHighest: AppColors.border,
        outline: AppColors.textMuted,
        outlineVariant: AppColors.border,
        error: AppColors.danger,
        onError: Colors.white,
        errorContainer: AppColors.dangerBg,
        onErrorContainer: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.inter,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.successDarkGreen,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.chipBg,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            headlineSmall: const TextStyle(
              fontFamily: AppFonts.outfit,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            titleLarge: const TextStyle(
              fontFamily: AppFonts.outfit,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            titleMedium: const TextStyle(
              fontFamily: AppFonts.outfit,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            titleSmall: const TextStyle(
              fontFamily: AppFonts.outfit,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            bodyMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary,
            ),
            bodySmall: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
            ),
            labelLarge: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        filled: true,
        fillColor: AppColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.outfit,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
    );
  }
}
