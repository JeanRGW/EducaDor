import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/repositories/company_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import 'widgets.dart';

class CompanyProfileScreen extends ConsumerWidget {
  const CompanyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final identity = ref.watch(companyIdentityProvider);
    final employees = ref.watch(companyEmployeesProvider);
    final company = identity.asData?.value;
    final name = company?.name ?? session?.active?.companyName ?? 'Empresa';
    return Theme(
      data: CompanyStyles.theme(Theme.of(context)),
      child: Scaffold(
        body: ListView(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  CompanyAvatar(
                    initials: companyInitials(name),
                    size: 72,
                    outlined: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: AdminStyles.formTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    company == null
                        ? identity.isLoading
                              ? 'Carregando dados da empresa...'
                              : 'Dados cadastrais indisponíveis'
                        : company.cnpj.isEmpty
                        ? 'CNPJ não informado'
                        : 'CNPJ: ${company.cnpj}',
                    textAlign: TextAlign.center,
                    style: AdminStyles.body.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      employees.asData == null
                          ? 'Gestor da empresa'
                          : '${employees.value!.length}${employees.value!.length == 50 ? '+' : ''} Funcionários',
                      style: AdminStyles.fieldLabel.copyWith(
                        color: AppColors.successDarkGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (identity.hasError) ...[
                    CompanyErrorCard(
                      message: 'Não foi possível carregar os dados cadastrais.',
                      retry: () => ref.invalidate(companyIdentityProvider),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _MenuRow(
                    'Gestores da empresa',
                    onTap: () => context.push('/empresa/gestores'),
                  ),
                  if ((session?.contexts.length ?? 0) > 1)
                    _MenuRow(
                      'Trocar perfil',
                      onTap: () => context.go('/contexts'),
                    ),
                  for (final label in [
                    'Notificações',
                    'Lembretes automáticos de treinamento',
                    'Gerenciar Departamento',
                    'Configurações',
                  ])
                    _MenuRow(
                      label,
                      onTap: () => showCompanyUnavailable(context, label),
                    ),
                  _MenuRow(
                    'Suporte',
                    subtitle: 'Canal de suporte em breve',
                    onTap: () => showCompanyUnavailable(context, 'Suporte'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.dangerBg,
                      foregroundColor: AppColors.danger,
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    onPressed: () async {
                      await ref.read(sessionProvider.notifier).logout();
                      if (context.mounted) context.go('/welcome');
                    },
                    child: const Row(
                      children: [
                        Expanded(child: Text('Sair')),
                        SvgIcon(
                          AppIcons.logout,
                          size: 18,
                          color: AppColors.danger,
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
    );
  }
}

class _MenuRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  const _MenuRow(this.label, {this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
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
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AdminStyles.body.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: CompanyStyles.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const SvgIcon(
                AppIcons.chevronRight,
                size: 18,
                color: Color(0xFF475569),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
