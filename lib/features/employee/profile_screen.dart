import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/employee_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/profile.dart';
import 'widgets.dart';

class EmployeeProfileScreen extends ConsumerWidget {
  const EmployeeProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final summary = ref.watch(employeeSummaryProvider);
    return ProfilePage(
      initials: session?.user.initials ?? '',
      name: session?.user.fullName ?? '',
      subtitle: summary.asData?.value.department.isNotEmpty == true
          ? summary.value!.department
          : 'Departamento não informado',
      badge: session?.active?.companyName ?? '',
      onRefresh: () async {
        ref.invalidate(employeeSummaryProvider);
        try {
          await ref.read(employeeSummaryProvider.future);
        } catch (_) {}
      },
      summary: EmployeeResult(
        result: summary,
        retry: () => ref.invalidate(employeeSummaryProvider),
        builder: (data) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (value, label) in [
              ('${data.completedCourseCount}', 'Concluídos'),
              ('${data.certificateCount}', 'Certificados'),
              ('${data.balance}', 'Pontos'),
            ])
              Expanded(
                child: Column(
                  children: [
                    Text(
                      value,
                      style: AdminStyles.formTitle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: AdminStyles.body.copyWith(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      settings: ProfileAccountSettings(
        editLocation: '/funcionario/perfil/edit',
        onProfileEdited: () => refreshLearning(ref),
      ),
    );
  }
}
