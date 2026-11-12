import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Shared typography and form treatment for the platform-management screens.
abstract class AdminStyles {
  static const pageTitle = TextStyle(
    letterSpacing: 0,
    fontFamily: AppFonts.outfit,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );
  static const formTitle = TextStyle(
    letterSpacing: 0,
    fontFamily: AppFonts.outfit,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  static const cardTitle = TextStyle(
    letterSpacing: 0,
    fontFamily: AppFonts.outfit,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  static const body = TextStyle(
    letterSpacing: 0,
    fontFamily: AppFonts.inter,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: Color(0xFF475569),
    height: 1.4,
  );
  static const fieldLabel = TextStyle(
    letterSpacing: 0,
    fontFamily: AppFonts.inter,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Color(0xFF475569),
    height: 1.4,
  );
  static const fieldText = TextStyle(
    letterSpacing: 0,
    fontFamily: AppFonts.inter,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: Color(0xFF475569),
    height: 1.25,
  );
  static const emptyState = TextStyle(
    letterSpacing: 0,
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
    final scheme = base.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return screenTheme(base).copyWith(
      textTheme: base.textTheme.copyWith(
        titleMedium: fieldText.copyWith(color: scheme.onSurface),
        bodyLarge: fieldText.copyWith(color: scheme.onSurface),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: fieldText.copyWith(color: scheme.onSurfaceVariant),
        isDense: true,
        contentPadding: const EdgeInsets.all(12),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        titleTextStyle: formTitle.copyWith(color: scheme.onSurface),
        leadingWidth: 48,
        titleSpacing: 0,
        toolbarHeight: 52,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
    );
  }
}
