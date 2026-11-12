import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/router.dart';
import 'offline_banner.dart';
import 'notification_feedback.dart';
import 'theme.dart';
import 'theme_preference.dart';

class EducaDorApp extends ConsumerWidget {
  const EducaDorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'EducaDor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themePreferenceProvider),
      routerConfig: router,
      builder: (context, child) => NotificationFeedback(
        child: OfflineBanner(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
