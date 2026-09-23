import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/common.dart';
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
    final companyId = widget.companyId ?? ref.read(sessionProvider).value?.active?.companyId;
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
      if (mounted) context.pop();
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (widget.role) {
        Role.gestor => 'Convidar gestor da plataforma',
        Role.empresa => 'Convidar gestor da empresa',
        Role.funcionario => 'Convidar funcionário',
      }),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'A pessoa receberá acesso ao aceitar o link compartilhado com ela.',
        ),
        const SizedBox(height: 20),
        FormFieldLabel(
          label: 'Nome completo',
          controller: _name,
          hint: 'Nome da pessoa',
        ),
        FormFieldLabel(
          label: 'E-mail',
          controller: _email,
          hint: 'pessoa@empresa.com',
        ),
        if (widget.role == Role.funcionario) ...[
          FormFieldLabel(
            label: 'Departamento',
            controller: _department,
            hint: 'RH',
          ),
          FormFieldLabel(
            label: 'Cargo / especialidade',
            controller: _jobTitle,
            hint: 'Analista',
          ),
        ],
        PrimaryButton(
          _busy ? 'Criando convite...' : 'Criar convite',
          onPressed: _busy ? null : _submit,
        ),
      ],
    ),
  );
}
