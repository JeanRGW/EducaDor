import 'package:educador/app/theme.dart';
import 'package:educador/shared/widgets/admin_styles.dart';
import 'package:educador/shared/widgets/common.dart';
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

  test('dark theme keeps component sizing and shapes from light', () {
    final light = AppTheme.light;
    final dark = AppTheme.dark;
    expect(
      dark.filledButtonTheme.style?.minimumSize?.resolve({}),
      light.filledButtonTheme.style?.minimumSize?.resolve({}),
    );
    expect(
      dark.outlinedButtonTheme.style?.minimumSize?.resolve({}),
      light.outlinedButtonTheme.style?.minimumSize?.resolve({}),
    );
    expect(
      dark.filledButtonTheme.style?.shape?.resolve({}),
      light.filledButtonTheme.style?.shape?.resolve({}),
    );
    expect(dark.floatingActionButtonTheme.shape, isA<CircleBorder>());
    expect(
      dark.progressIndicatorTheme.linearTrackColor,
      dark.colorScheme.surfaceContainerHigh,
    );
    expect(dark.appBarTheme.toolbarHeight, light.appBarTheme.toolbarHeight);
    expect(
      dark.inputDecorationTheme.contentPadding,
      light.inputDecorationTheme.contentPadding,
    );
    expect(
      dark.textTheme.headlineSmall?.fontSize,
      light.textTheme.headlineSmall?.fontSize,
    );
  });

  test('semantic palette adapts per brightness and matches light values', () {
    final light = AppTheme.light.colorScheme;
    final dark = AppTheme.dark.colorScheme;
    expect(light.successSurface, AppColors.successBg);
    expect(light.successForeground, AppColors.successDarkGreen);
    expect(light.dangerSurface, AppColors.dangerBg);
    expect(dark.successSurface, isNot(AppColors.successBg));
    expect(
      contrast(dark.successForeground, dark.successSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(dark.dangerForeground, dark.dangerSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('light theme stays light', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.light.scaffoldBackgroundColor, AppColors.background);
  });

  testWidgets('primary button follows the active scheme', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: PrimaryButton('Continuar')),
        ),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(
        button.style?.backgroundColor?.resolve({}),
        theme.colorScheme.primary,
      );
      expect(
        button.style?.foregroundColor?.resolve({}),
        theme.colorScheme.onPrimary,
      );
    }
  });

  testWidgets('floating action keeps the scheme foreground legible', (
    tester,
  ) async {
    final theme = AppTheme.dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          floatingActionButton: const FloatingActionButton(
            onPressed: null,
            child: Icon(Icons.add),
          ),
        ),
      ),
    );
    expect(
      theme.floatingActionButtonTheme.backgroundColor,
      theme.colorScheme.primary,
    );
    expect(
      theme.floatingActionButtonTheme.foregroundColor,
      theme.colorScheme.onPrimary,
    );
  });
}
