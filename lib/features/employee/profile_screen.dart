import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../data/repositories/employee_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../company/widgets.dart' show CompanyAvatar;
import 'widgets.dart';

class EmployeeProfileScreen extends ConsumerWidget {
  const EmployeeProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final summary = ref.watch(employeeSummaryProvider);
    return Theme(
      data: EmployeeStyles.theme(Theme.of(context)),
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(employeeSummaryProvider);
            try {
              await ref.read(employeeSummaryProvider.future);
            } catch (_) {}
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Column(
                  children: [
                    CompanyAvatar(
                      initials: session?.user.initials ?? '',
                      size: 72,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      session?.user.fullName ?? '',
                      style: AdminStyles.pageTitle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.asData?.value.department.isNotEmpty == true
                          ? summary.value!.department
                          : 'Departamento não informado',
                      style: AdminStyles.body.copyWith(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successBgSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        session?.active?.companyName ?? '',
                        style: AdminStyles.fieldLabel.copyWith(
                          color: AppColors.successDarkGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    EmployeeResult(
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
                                    style: AdminStyles.pageTitle.copyWith(
                                      fontSize: 18,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    label,
                                    style: AdminStyles.body.copyWith(
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'CONFIGURAÇÕES DE CONTA',
                      style: AdminStyles.cardTitle.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _row(
                      'Editar dados pessoais',
                      AppIcons.manageAccount,
                      () async {
                        await context.push('/funcionario/perfil/edit');
                        if (context.mounted) {
                          refreshLearning(ref);
                        }
                      },
                    ),
                    _row(
                      'Notificações',
                      AppIcons.bell,
                      null,
                      status: 'Em breve',
                    ),
                    _row(
                      'Idioma',
                      AppIcons.globe,
                      null,
                      status: 'Português (Brasil)',
                    ),
                    _row(
                      'Modo escuro',
                      AppIcons.moon,
                      null,
                      status: 'Em breve',
                    ),
                    _row(
                      'Suporte e ajuda',
                      AppIcons.help,
                      null,
                      status: 'Em breve',
                    ),
                    if ((session?.contexts.length ?? 0) > 1)
                      _row(
                        'Trocar perfil',
                        AppIcons.profile,
                        () => context.go('/contexts'),
                      ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        backgroundColor: AppColors.surface,
                        side: BorderSide(
                          color: AppColors.danger.withValues(alpha: 0.2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () async {
                        await ref.read(sessionProvider.notifier).logout();
                        if (context.mounted) context.go('/welcome');
                      },
                      icon: const SvgIcon(
                        AppIcons.logout,
                        color: AppColors.danger,
                        size: 18,
                      ),
                      label: const Text('Sair'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    String label,
    String icon,
    VoidCallback? onTap, {
    String? status,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SvgIcon(icon, color: const Color(0xFF475569), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: AdminStyles.body.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      status,
                      style: AdminStyles.body.copyWith(fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
                if (onTap != null)
                  const SvgIcon(
                    AppIcons.chevronRight,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
