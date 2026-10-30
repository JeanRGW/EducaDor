import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/common.dart';
import '../auth/onboarding_screens.dart';
import '../content/catalog_screen.dart';
import '../content/publish_video_screen.dart';
import 'widgets.dart';

export 'companies_screen.dart';
export 'dashboard_screen.dart';
export 'reports_screen.dart';
export 'profile_screen.dart';

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
            color: AppColors.primary,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    ),
  );
}
