import 'dart:async';

import 'package:educador/app/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');

  test('failed platform write does not poison a later load', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') return <String, Object>{};
          if (call.method == 'setString') return false;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await expectLater(
      first.read(themePreferenceProvider.notifier).setMode(ThemeMode.dark),
      throwsStateError,
    );
    expect(first.read(themePreferenceProvider), ThemeMode.light);
    final next = ProviderContainer();
    addTearDown(next.dispose);
    await next.read(themePreferenceProvider.notifier).load();
    expect(next.read(themePreferenceProvider), ThemeMode.light);
  });

  test('superseded failure is silent while latest write succeeds', () async {
    final gate = Completer<bool>();
    final values = <String, Object>{};
    var writes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') return Map<String, Object>.of(values);
          if (call.method == 'setString') {
            if (++writes == 1) return gate.future;
            values[call.arguments['key'] as String] =
                call.arguments['value'] as Object;
            return true;
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(themePreferenceProvider.notifier);
    final first = notifier.setMode(ThemeMode.dark);
    final latest = notifier.setMode(ThemeMode.light);
    gate.complete(false);
    await Future.wait([first, latest]);
    expect(container.read(themePreferenceProvider), ThemeMode.light);
    expect(values['flutter.theme_mode'], 'light');
  });
}
