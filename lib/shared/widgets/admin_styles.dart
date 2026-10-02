import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Shared typography and form treatment for the platform-management screens.
abstract class AdminStyles {
  static const pageTitle = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );
  static const formTitle = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  static const cardTitle = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  static const body = TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: Color(0xFF475569),
    height: 1.4,
  );
  static const fieldLabel = TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Color(0xFF475569),
    height: 1.4,
  );
  static const fieldText = TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: Color(0xFF475569),
    height: 1.25,
  );
  static const emptyState = TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Color(0xFF475569),
    height: 1.4,
  );

  // Desktop defaults otherwise shrink Material controls but not custom fields.
  static ThemeData screenTheme(ThemeData base) =>
      base.copyWith(visualDensity: VisualDensity.standard);

  static ThemeData formTheme(ThemeData base) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return screenTheme(base).copyWith(
      textTheme: base.textTheme.copyWith(
        titleMedium: fieldText,
        bodyLarge: fieldText,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: fieldText.copyWith(color: AppColors.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.all(12),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(
            color: AppColors.successDarkGreen,
            width: 1.6,
          ),
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.surface,
        titleTextStyle: formTitle,
        leadingWidth: 48,
        titleSpacing: 0,
        toolbarHeight: 52,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
    );
  }
}
