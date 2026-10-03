import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../company/widgets.dart';
import '../gestor/management_widgets.dart' show leaveManagementPage;
import 'onboarding_screens.dart';

class AddPlatformManagerScreen extends StatelessWidget {
  const AddPlatformManagerScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const InvitePersonScreen(role: Role.gestor);
}

class AddCompanyManagerScreen extends StatelessWidget {
  const AddCompanyManagerScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const InvitePersonScreen(role: Role.empresa);
}

class AddPlatformCompanyManagerScreen extends StatelessWidget {
  final String companyId;
  const AddPlatformCompanyManagerScreen({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) =>
      InvitePersonScreen(role: Role.empresa, companyId: companyId);
}

class AddEmployeeScreen extends StatelessWidget {
  const AddEmployeeScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const InvitePersonScreen(role: Role.funcionario);
}

class InvitePersonScreen extends ConsumerStatefulWidget {
  final Role role;
  final String? companyId;
  const InvitePersonScreen({super.key, required this.role, this.companyId});

  @override
  ConsumerState<InvitePersonScreen> createState() => _InvitePersonScreenState();
}

class _InvitePersonScreenState extends ConsumerState<InvitePersonScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _department = TextEditingController();
  final _jobTitle = TextEditingController();
  bool _busy = false;

  void _leave() => leaveManagementPage(context, switch (widget.role) {
    Role.gestor => '/gestor/gestores',
    Role.empresa =>
      widget.companyId == null
          ? '/empresa/gestores'
          : '/gestor/company/${widget.companyId}/gestores',
    Role.funcionario => '/empresa/funcionarios',
  });

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _department.dispose();
    _jobTitle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe nome e e-mail válidos.')),
      );
      return;
    }
    final companyId =
        widget.companyId ?? ref.read(sessionProvider).value?.active?.companyId;
    if (widget.role != Role.gestor && companyId == null) return;
    setState(() => _busy = true);
    try {
      final link = await ref
          .read(invitationRepositoryProvider)
          .invite(
            role: widget.role,
            name: _name.text,
            email: _email.text,
            companyId: companyId,
            department: widget.role == Role.funcionario
                ? _department.text
                : null,
            jobTitle: widget.role == Role.funcionario ? _jobTitle.text : null,
          );
      if (!mounted) return;
      await showInviteLink(context, link);
      if (mounted) _leave();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível criar o convite. Verifique os dados.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = widget.role == Role.gestor || widget.companyId != null;
    return Theme(
      data: platform
          ? AdminStyles.formTheme(Theme.of(context))
          : CompanyStyles.theme(Theme.of(context)).copyWith(
              appBarTheme: AdminStyles.formTheme(Theme.of(context)).appBarTheme,
            ),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(context).scale(18) > 22
              ? 72
              : 52,
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _leave,
            icon: const SvgIcon(
              AppIcons.arrowBack,
              size: 20,
              color: AppColors.successDarkGreen,
            ),
          ),
          title: Text(switch (widget.role) {
            Role.gestor => 'Convidar gestor da plataforma',
            Role.empresa => 'Convidar gestor da empresa',
            Role.funcionario => 'Convidar funcionário',
          }, maxLines: 2),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'A pessoa receberá acesso ao aceitar o link compartilhado com ela.',
              style: AdminStyles.body,
            ),
            const SizedBox(height: 20),
            FormFieldLabel(
              label: platform ? 'Nome completo' : 'NOME COMPLETO',
              compact: true,
              controller: _name,
              hint: 'Nome da pessoa',
            ),
            FormFieldLabel(
              label: platform ? 'E-mail' : 'EMAIL',
              compact: true,
              controller: _email,
              hint: 'pessoa@empresa.com',
            ),
            if (widget.role == Role.funcionario) ...[
              FormFieldLabel(
                label: platform ? 'Departamento' : 'DEPARTAMENTO',
                compact: true,
                controller: _department,
                hint: 'RH',
              ),
              FormFieldLabel(
                label: platform
                    ? 'Cargo / especialidade'
                    : 'CARGO / ESPECIALIDADE',
                compact: true,
                controller: _jobTitle,
                hint: 'Analista',
              ),
            ],
            PrimaryButton(
              _busy ? 'Criando convite...' : 'Criar convite',
              compact: true,
              color: AppColors.successDarkGreen,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
