import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Shared typography and form treatment for the platform-management screens.
abstract class AdminStyles {
  static TextStyle pageTitleFor(ColorScheme scheme) =>
      _outfit(scheme.onSurface, 20, 1.2);
  static TextStyle formTitleFor(ColorScheme scheme) =>
      _outfit(scheme.onSurface, 18, 1.3);
  static TextStyle cardTitleFor(ColorScheme scheme) =>
      _outfit(scheme.onSurface, 14, 1.3);
  static TextStyle bodyFor(ColorScheme scheme) =>
      _body(scheme.onSurfaceVariant, 13, FontWeight.w400, 1.4);
  static TextStyle fieldLabelFor(ColorScheme scheme) =>
      _body(scheme.onSurfaceVariant, 12, FontWeight.w600, 1.4);
  static TextStyle fieldTextFor(ColorScheme scheme, {bool muted = false}) =>
      _body(
        muted ? scheme.onSurfaceVariant : scheme.onSurface,
        13,
        FontWeight.w400,
        1.25,
      );
  static TextStyle emptyStateFor(ColorScheme scheme) =>
      _body(scheme.onSurfaceVariant, 12, FontWeight.w400, 1.4);

  static TextStyle _outfit(Color color, double size, double height) =>
      TextStyle(
        letterSpacing: 0,
        fontFamily: AppFonts.outfit,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        height: height,
      );
  static TextStyle _body(
    Color color,
    double size,
    FontWeight weight,
    double height,
  ) => TextStyle(
    letterSpacing: 0,
    fontFamily: AppFonts.inter,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );

  static TextStyle pageTitle(BuildContext context) =>
      pageTitleFor(Theme.of(context).colorScheme);
  static TextStyle formTitle(BuildContext context) =>
      formTitleFor(Theme.of(context).colorScheme);
  static TextStyle cardTitle(BuildContext context) =>
      cardTitleFor(Theme.of(context).colorScheme);
  static TextStyle body(BuildContext context) =>
      bodyFor(Theme.of(context).colorScheme);
  static TextStyle fieldLabel(BuildContext context) =>
      fieldLabelFor(Theme.of(context).colorScheme);
  static TextStyle fieldText(BuildContext context) =>
      fieldTextFor(Theme.of(context).colorScheme);
  static TextStyle emptyState(BuildContext context) =>
      emptyStateFor(Theme.of(context).colorScheme);

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
        titleMedium: fieldTextFor(scheme),
        bodyLarge: fieldTextFor(scheme),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: fieldTextFor(scheme, muted: true),
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
        titleTextStyle: formTitleFor(scheme),
        leadingWidth: 48,
        titleSpacing: 0,
        toolbarHeight: 52,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
    );
  }
}
