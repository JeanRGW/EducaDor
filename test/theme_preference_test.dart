import 'package:educador/app/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rapid changes persist the latest selection', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(themePreferenceProvider.notifier);
    await Future.wait([
      notifier.setMode(ThemeMode.dark),
      notifier.setMode(ThemeMode.light),
      notifier.setMode(ThemeMode.dark),
    ]);
    expect(container.read(themePreferenceProvider), ThemeMode.dark);
    expect(
      (await SharedPreferences.getInstance()).getString(themePreferenceKey),
      'dark',
    );
  });

  test('system mode persists alongside explicit modes', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(themePreferenceProvider.notifier)
        .setMode(ThemeMode.system);
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(themePreferenceProvider.notifier).load();
    expect(restored.read(themePreferenceProvider), ThemeMode.system);
  });

  test('preference persists and can be restored', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    addTearDown(first.dispose);
    expect(first.read(themePreferenceProvider), ThemeMode.light);
    await first.read(themePreferenceProvider.notifier).setMode(ThemeMode.dark);

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(themePreferenceProvider.notifier).load();
    expect(restored.read(themePreferenceProvider), ThemeMode.dark);
  });
}
