import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/common.dart';
import 'management_widgets.dart';
import 'widgets.dart';

class CompanyDetailScreen extends ConsumerStatefulWidget {
  final String companyId;
  const CompanyDetailScreen({super.key, required this.companyId});
  @override
  ConsumerState<CompanyDetailScreen> createState() =>
      _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends ConsumerState<CompanyDetailScreen> {
  late Future<Company> _company;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _company = ref.read(companyRepositoryProvider).byId(widget.companyId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Company>(
    future: _company,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return _CompanyEditor(
          key: ValueKey(snapshot.data),
          company: snapshot.data!,
        );
      }
      return ManagementPage(
        title: 'Detalhes da empresa',
        fallbackLocation: '/gestor/empresas',
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (snapshot.hasError)
              DataErrorCard(
                message: 'Empresa indisponível. Tente carregar novamente.',
                retry: () => setState(_load),
              )
            else
              const DataSkeleton(),
          ],
        ),
      );
    },
  );
}

class _CompanyEditor extends ConsumerStatefulWidget {
  final Company company;
  const _CompanyEditor({super.key, required this.company});
  @override
  ConsumerState<_CompanyEditor> createState() => _CompanyEditorState();
}

class _CompanyEditorState extends ConsumerState<_CompanyEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late bool _active;
  bool _busy = false;
  static const _labels = {
    'name': 'Nome da empresa',
    'cnpj': 'CNPJ',
    'responsible': 'Pessoa responsável',
    'email': 'E-mail de contato',
    'phone': 'Telefone',
    'address': 'Endereço',
    'city': 'Cidade',
    'state': 'Estado',
    'field': 'Área de atuação',
  };

  @override
  void initState() {
    super.initState();
    final c = widget.company;
    _active = c.active;
    _fields = {
      'name': c.name,
      'cnpj': c.cnpj,
      'responsible': c.responsibleName,
      'email': c.email,
      'phone': c.phone,
      'address': c.address,
      'city': c.city,
      'state': c.state,
      'field': c.field,
    }.map((key, value) => MapEntry(key, TextEditingController(text: value)));
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    ref.invalidate(gestorCompaniesProvider);
    ref.invalidate(gestorDashboardProvider);
    ref.invalidate(gestorCompletionProvider);
    await ref.read(sessionProvider.notifier).reload();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(companyRepositoryProvider)
          .update(
            widget.company.id,
            _fields.map((key, value) => MapEntry(key, value.text.trim())),
          );
      if (mounted) showManagementMessage(context, 'Dados da empresa salvos.');
      await _refreshData();
    } catch (error) {
      if (mounted) {
        showManagementMessage(
          context,
          managementError(
            error,
            'Não foi possível salvar ou atualizar os dados. Tente novamente.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final active = !_active;
    final confirmed = await confirmManagementAction(
      context,
      title: active ? 'Reativar empresa?' : 'Pausar empresa?',
      message: active
          ? 'Os gestores e funcionários poderão acessar esta empresa novamente.'
          : 'Os gestores e funcionários perderão acesso a esta empresa enquanto ela estiver pausada. Os vínculos e o progresso serão preservados.',
      action: active ? 'Reativar empresa' : 'Pausar empresa',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(companyRepositoryProvider)
          .setActive(widget.company.id, active);
      if (mounted) {
        setState(() => _active = active);
        showManagementMessage(
          context,
          active ? 'Empresa reativada.' : 'Empresa pausada.',
        );
      }
      await _refreshData();
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível atualizar a empresa. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key) => ManagementField(
    label: _labels[key]!,
    labelAbove: true,
    controller: _fields[key]!,
    enabled: !_busy,
    requiredValue: key == 'name',
    maxLength: key == 'address' ? 500 : 200,
    keyboardType: key == 'email'
        ? TextInputType.emailAddress
        : key == 'phone'
        ? TextInputType.phone
        : null,
    validator: key == 'email'
        ? (value) =>
              value!.trim().isNotEmpty &&
                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())
              ? 'Informe um e-mail válido.'
              : null
        : null,
  );

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: 'Detalhes da empresa',
    fallbackLocation: '/gestor/empresas',
    busy: _busy,
    child: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _active ? 'Empresa ativa' : 'Empresa pausada',
                  style: AdminStyles.cardTitle.copyWith(
                    color: _active
                        ? AppColors.successDarkGreen
                        : AppColors.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Registro: ${widget.company.registeredAt.isEmpty ? '—' : formatDate(DateTime.parse(widget.company.registeredAt))}',
                  style: AdminStyles.body,
                ),
                const SizedBox(height: 12),
                OutlinedButtonTheme(
                  data: OutlinedButtonThemeData(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.successDarkGreen,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: AdminStyles.fieldLabel,
                    ),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : _toggle,
                        child: Text(
                          _active ? 'Pausar empresa' : 'Reativar empresa',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => context.push(
                                '/gestor/company/${widget.company.id}/gestores',
                              ),
                        child: const Text('Gerenciar gestores da empresa'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _field('name'),
          _field('cnpj'),
          _field('responsible'),
          CompanyFieldRow(first: _field('email'), second: _field('phone')),
          _field('address'),
          CompanyFieldRow(
            firstFlex: 3,
            first: _field('city'),
            second: _field('state'),
          ),
          _field('field'),
          const SizedBox(height: 4),
          PrimaryButton(
            _busy ? 'Salvando...' : 'Salvar dados da empresa',
            compact: true,
            color: AppColors.successDarkGreen,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    ),
  );
}
