import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/company_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/profile.dart';
import 'widgets.dart';

class CompanyProfileScreen extends ConsumerWidget {
  const CompanyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final identity = ref.watch(companyIdentityProvider);
    final dashboard = ref.watch(companyDashboardProvider);
    final company = identity.asData?.value;
    final name = company?.name ?? session?.active?.companyName ?? 'Empresa';
    return ProfilePage(
      initials: companyInitials(name),
      name: name,
      subtitle: company == null
          ? identity.isLoading
                ? 'Carregando dados da empresa...'
                : 'Dados cadastrais indisponíveis'
          : company.cnpj.isEmpty
          ? 'CNPJ não informado'
          : 'CNPJ: ${company.cnpj}',
      badge: dashboard.asData == null
          ? 'Gestor da empresa'
          : '${dashboard.value!.employeeCount} funcionários',
      settings: ProfileAccountSettings(
        editLocation: '/empresa/perfil/edit',
        notices: [
          if (identity.hasError) ...[
            CompanyErrorCard(
              message: 'Não foi possível carregar os dados cadastrais.',
              retry: () => ref.invalidate(companyIdentityProvider),
            ),
            const SizedBox(height: 8),
          ],
          if (dashboard.hasError) ...[
            CompanyErrorCard(
              message: 'Não foi possível carregar o total de funcionários.',
              retry: () => ref.invalidate(companyDashboardProvider),
            ),
            const SizedBox(height: 8),
          ],
        ],
        managementActions: [
          ProfileMenuRow(
            label: 'Gestores da empresa',
            icon: AppIcons.groups,
            onTap: () => context.push('/empresa/gestores'),
          ),
          const ProfileMenuRow(
            label: 'Lembretes automáticos de treinamento',
            icon: AppIcons.clock,
            status: 'Em breve',
          ),
          const ProfileMenuRow(
            label: 'Gerenciar departamentos',
            icon: AppIcons.briefcase,
            status: 'Em breve',
          ),
        ],
      ),
    );
  }
}
