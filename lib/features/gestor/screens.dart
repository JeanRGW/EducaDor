import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/common.dart';
import '../auth/onboarding_screens.dart';
import '../auth/pending_invites.dart';
import '../content/catalog_screen.dart';
import '../content/publish_video_screen.dart';
import 'widgets.dart';

export 'companies_screen.dart';
export 'dashboard_screen.dart';
export 'reports_screen.dart';

class ContentManagementScreen extends StatelessWidget {
  const ContentManagementScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const ContentCatalogScreen(platform: true);
}

class AddTrailScreen extends StatelessWidget {
  const AddTrailScreen({super.key});
  @override
  Widget build(BuildContext context) => const PublishVideoScreen();
}

class AddCompanyScreen extends ConsumerStatefulWidget {
  const AddCompanyScreen({super.key});
  @override
  ConsumerState<AddCompanyScreen> createState() => _AddCompanyScreenState();
}

class _AddCompanyScreenState extends ConsumerState<AddCompanyScreen> {
  final _name = TextEditingController();
  final _cnpj = TextEditingController();
  final _responsible = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _address = TextEditingController();
  final _field = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _cnpj,
      _responsible,
      _email,
      _phone,
      _city,
      _state,
      _address,
      _field,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty ||
        _responsible.text.trim().isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe empresa, responsável e e-mail válidos.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final link = await ref
          .read(invitationRepositoryProvider)
          .invite(
            role: Role.empresa,
            name: _responsible.text,
            email: _email.text,
            company: {
              'name': _name.text.trim(),
              'cnpj': _cnpj.text.trim(),
              'responsible': _responsible.text.trim(),
              'email': _email.text.trim(),
              'phone': _phone.text.trim(),
              'city': _city.text.trim(),
              'state': _state.text.trim(),
              'address': _address.text.trim(),
              'field': _field.text.trim(),
            },
          );
      if (!mounted) return;
      await showInviteLink(context, link);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível criar a empresa e o convite.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AdminStyles.formTheme(Theme.of(context)),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar empresa'),
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const SvgIcon(
            AppIcons.arrowBack,
            size: 20,
            color: AppColors.successDarkGreen,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          FormFieldLabel(
            label: 'Nome da Empresa',
            compact: true,
            hint: 'santa maria',
            controller: _name,
          ),
          FormFieldLabel(
            label: 'CNPJ',
            compact: true,
            hint: '00.000.000/0001-00',
            controller: _cnpj,
          ),
          FormFieldLabel(
            label: 'Primeiro gestor da empresa',
            compact: true,
            hint: 'Nome completo',
            controller: _responsible,
          ),
          CompanyFieldRow(
            first: FormFieldLabel(
              label: 'E-mail do gestor',
              compact: true,
              hint: 'admin@comp.com',
              controller: _email,
            ),
            second: FormFieldLabel(
              label: 'Telefone',
              compact: true,
              hint: '(31) 99999-9999',
              controller: _phone,
            ),
          ),
          FormFieldLabel(
            label: 'Endereço',
            compact: true,
            hint: 'Rua, número, bairro',
            controller: _address,
          ),
          CompanyFieldRow(
            firstFlex: 3,
            first: FormFieldLabel(
              label: 'Cidade',
              compact: true,
              hint: 'Belo Horizonte',
              controller: _city,
            ),
            second: FormFieldLabel(
              label: 'Estado',
              compact: true,
              hint: 'MG',
              controller: _state,
            ),
          ),
          FormFieldLabel(
            label: 'Área de atuação',
            compact: true,
            hint: 'Saúde',
            controller: _field,
          ),
          const SizedBox(height: 4),
          PrimaryButton(
            _busy ? 'Criando...' : 'Criar empresa e convite',
            compact: true,
            color: AppColors.successDarkGreen,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    ),
  );
}

class GestorProfileScreen extends ConsumerStatefulWidget {
  const GestorProfileScreen({super.key});
  @override
  ConsumerState<GestorProfileScreen> createState() =>
      _GestorProfileScreenState();
}

class _GestorProfileScreenState extends ConsumerState<GestorProfileScreen> {
  int _pendingRevision = 0;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    return Theme(
      data: AdminStyles.screenTheme(Theme.of(context)),
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.successDarkGreen,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        session?.user.initials ?? '',
                        style: const TextStyle(
                          fontFamily: AppFonts.outfit,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.successDarkGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        session?.user.fullName ?? 'Gestor',
                        textAlign: TextAlign.center,
                        style: AdminStyles.formTitle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        session?.user.email ?? '',
                        textAlign: TextAlign.center,
                        style: AdminStyles.body.copyWith(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            'SUPER ADMIN',
                            style: TextStyle(
                              fontFamily: AppFonts.inter,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.successDarkGreen,
                              height: 1.2,
                            ),
                          ),
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
                    PrimaryButton(
                      'Convidar gestor da plataforma',
                      compact: true,
                      color: AppColors.successDarkGreen,
                      onPressed: () async {
                        await context.push('/gestor/manager/add');
                        if (mounted) setState(() => _pendingRevision++);
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => context.push('/gestor/gestores'),
                      child: const Text('Gerenciar gestores da plataforma'),
                    ),
                    const SizedBox(height: 12),
                    PendingInvitesSection(
                      key: ValueKey((_pendingRevision, session?.user.id)),
                      role: Role.gestor,
                    ),
                    const SizedBox(height: 12),
                    if ((session?.contexts.length ?? 0) > 1) ...[
                      OutlinedButton(
                        onPressed: () => context.go('/contexts'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.successDarkGreen,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(color: AppColors.border),
                          textStyle: const TextStyle(
                            fontFamily: AppFonts.inter,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Trocar perfil'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _GestorMenuRow(
                      AppIcons.accountEdit,
                      'Configurações de Conta',
                      onTap: () => context.push('/gestor/perfil/edit'),
                    ),
                    const _GestorMenuRow(
                      AppIcons.bell,
                      'Preferências de notificação',
                    ),
                    const _GestorMenuRow(AppIcons.security, 'Segurança e MFA'),
                    const _GestorMenuRow(
                      AppIcons.settings,
                      'Configurações da plataforma',
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await ref.read(sessionProvider.notifier).logout();
                        if (context.mounted) context.go('/welcome');
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: AppColors.danger),
                        foregroundColor: AppColors.danger,
                        backgroundColor: AppColors.dangerBg,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SvgIcon(
                            AppIcons.userOff,
                            size: 20,
                            color: AppColors.danger,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Sair',
                            style: TextStyle(
                              fontFamily: AppFonts.inter,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
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
      ),
    );
  }
}

class _GestorMenuRow extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  const _GestorMenuRow(this.icon, this.label, {this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SvgIcon(icon, size: 18, color: AppColors.successDarkGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AdminStyles.body.copyWith(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SvgIcon(
            AppIcons.chevronRight,
            size: 16,
            color: AppColors.textMuted,
          ),
        ],
      ),
    ),
  );
}
