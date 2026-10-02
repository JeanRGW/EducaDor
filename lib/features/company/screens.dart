import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/session/session_controller.dart';
import '../content/catalog_screen.dart';
import 'completion_screen.dart';
import 'widgets.dart';

export 'dashboard_screen.dart';
export 'employees_screen.dart';
export 'profile_screen.dart';

class CompanyContentScreen extends ConsumerWidget {
  const CompanyContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyId = ref.watch(sessionProvider).value?.active?.companyId;
    return Theme(
      data: CompanyStyles.theme(Theme.of(context)),
      child: ContentCatalogScreen(key: ValueKey(companyId), platform: false),
    );
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) => const CompanyCompletionScreen();
}
