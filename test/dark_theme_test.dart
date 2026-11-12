import 'package:educador/app/theme.dart';
import 'package:educador/shared/widgets/admin_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final luminances = [a.computeLuminance(), b.computeLuminance()]..sort();
  return (luminances.last + 0.05) / (luminances.first + 0.05);
}

void main() {
  test('dark theme text and controls contrast against their surfaces', () {
    final theme = AppTheme.dark;
    final scheme = theme.colorScheme;
    expect(theme.brightness, Brightness.dark);
    expect(
      contrast(scheme.onSurface, scheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.onSurfaceVariant, scheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.onPrimary, scheme.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.onSurface, theme.scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('management form respects the active color scheme', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final form = AdminStyles.formTheme(theme);
      expect(form.appBarTheme.backgroundColor, theme.colorScheme.surface);
      expect(form.textTheme.bodyLarge?.color, theme.colorScheme.onSurface);
      expect(
        form.inputDecorationTheme.hintStyle?.color,
        theme.colorScheme.onSurfaceVariant,
      );
    }
  });

  test('light theme stays light', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.light.scaffoldBackgroundColor, AppColors.background);
  });
}
