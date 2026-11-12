import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/theme_preference.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
  const url = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isNotEmpty && anonKey.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: anonKey);
  }
  final container = ProviderContainer();
  try {
    await container.read(themePreferenceProvider.notifier).load();
  } catch (_) {
    // Storage may be unavailable; keep the default light theme.
  }
  runApp(
    UncontrolledProviderScope(container: container, child: const EducaDorApp()),
  );
}
