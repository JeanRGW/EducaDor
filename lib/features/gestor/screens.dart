import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../auth/onboarding_screens.dart';
import '../auth/pending_invites.dart';
import '../content/catalog_screen.dart';
import '../content/publish_video_screen.dart';

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Adicionar empresa'),
      leading: IconButton(
        icon: const SvgIcon(AppIcons.arrowBack),
        onPressed: () => context.pop(),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FormFieldLabel(
          label: 'Nome da Empresa',
          hint: 'santa maria',
          controller: _name,
        ),
        FormFieldLabel(
          label: 'CNPJ',
          hint: '00.000.000/0001-00',
          controller: _cnpj,
        ),
        FormFieldLabel(
          label: 'Primeiro gestor da empresa',
          hint: 'Nome completo',
          controller: _responsible,
        ),
        Row(
          children: [
            Expanded(
              child: FormFieldLabel(
                label: 'E-mail do gestor',
                hint: 'admin@comp.com',
                controller: _email,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FormFieldLabel(
                label: 'Telefone',
                hint: '(31) 99999-9999',
                controller: _phone,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: FormFieldLabel(
                label: 'Cidade',
                hint: 'Belo Horizonte',
                controller: _city,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FormFieldLabel(
                label: 'Estado',
                hint: 'MG',
                controller: _state,
              ),
            ),
          ],
        ),
        FormFieldLabel(
          label: 'Endereço',
          hint: 'Rua, número, bairro',
          controller: _address,
        ),
        FormFieldLabel(
          label: 'Área de atuação',
          hint: 'Saúde',
          controller: _field,
        ),
        const SizedBox(height: 4),
        PrimaryButton(
          _busy ? 'Criando...' : 'Criar empresa e convite',
          onPressed: _busy ? null : _submit,
        ),
      ],
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
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: AvatarBadge(session?.user.initials ?? '', size: 84)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              session?.user.fullName ?? 'Gestor',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              session?.user.email ?? '',
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: StatusChip(
              'SUPER ADMIN',
              color: AppColors.successDarkGreen,
              bg: AppColors.successBg,
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            'Convidar gestor da plataforma',
            onPressed: () async {
              await context.push('/gestor/manager/add');
              if (mounted) setState(() => _pendingRevision++);
            },
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
              child: const Text('Trocar perfil'),
            ),
            const SizedBox(height: 12),
          ],
          const _GestorMenuRow(
            AppIcons.manageAccount,
            'Configurações de Conta',
          ),
          const _GestorMenuRow(AppIcons.bell, 'Preferências de notificação'),
          const _GestorMenuRow(AppIcons.shield, 'Segurança e MFA'),
          const _GestorMenuRow(
            AppIcons.settings,
            'Configurações da plataforma',
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go('/welcome');
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: const BorderSide(color: AppColors.danger),
              foregroundColor: AppColors.danger,
              backgroundColor: AppColors.dangerBg,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgIcon(AppIcons.logout, size: 18),
                SizedBox(width: 8),
                Text(
                  'Sair',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GestorMenuRow extends StatelessWidget {
  final String icon;
  final String label;
  const _GestorMenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        SvgIcon(icon, size: 20, color: AppColors.successDarkGreen),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ),
        const SvgIcon(AppIcons.chevronRight, color: AppColors.textMuted),
      ],
    ),
  );
}
