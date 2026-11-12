import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const themePreferenceKey = 'theme_mode';

final themePreferenceProvider = NotifierProvider<ThemePreference, ThemeMode>(
  ThemePreference.new,
);

class ThemePreference extends Notifier<ThemeMode> {
  int _revision = 0;
  Future<void> _pendingWrite = Future.value();
  ThemeMode _savedMode = ThemeMode.light;

  @override
  ThemeMode build() => ThemeMode.light;

  Future<void> load() async {
    final revision = _revision;
    final preferences = await SharedPreferences.getInstance();
    final mode = switch (preferences.getString(themePreferenceKey)) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    if (revision == _revision) {
      _savedMode = mode;
      state = mode;
    }
  }

  Future<void> setMode(ThemeMode mode) {
    final revision = ++_revision;
    state = mode;
    final write = _pendingWrite.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      try {
        if (!await preferences.setString(themePreferenceKey, mode.name)) {
          throw StateError('Could not save theme preference');
        }
      } catch (_) {
        // The legacy API updates its cache before the platform write. Discard
        // that optimistic value before a later load or provider can see it.
        try {
          await preferences.reload();
        } catch (_) {
          // Keep the original write failure.
        }
        rethrow;
      }
      _savedMode = mode;
    });
    _pendingWrite = write.catchError((Object _) {});
    return write.catchError((Object error, StackTrace stack) {
      if (revision != _revision) return;
      state = _savedMode;
      Error.throwWithStackTrace(error, stack);
    });
  }
}
