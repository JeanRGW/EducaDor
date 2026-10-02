import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import 'management_widgets.dart';
import 'widgets.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});
  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late Future<OwnProfile> _profile;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _profile = ref.read(profileRepositoryProvider).own();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<OwnProfile>(
    future: _profile,
    builder: (context, snapshot) {
      if (snapshot.hasData) return _ProfileEditor(profile: snapshot.data!);
      return ManagementPage(
        title: 'Configurações de conta',
        fallbackLocation: '/gestor/perfil',
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (snapshot.hasError)
              DataErrorCard(
                message: 'Não foi possível carregar seu perfil.',
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

class _ProfileEditor extends ConsumerStatefulWidget {
  final OwnProfile profile;
  const _ProfileEditor({required this.profile});
  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _phone, _address;
  late DateTime? _birthDate;
  bool _busy = false;
  bool _needsRefresh = false;
  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p.fullName);
    _phone = TextEditingController(text: p.phone);
    _address = TextEditingController(text: p.address);
    _birthDate = p.birthDate == null ? null : DateTime.parse(p.birthDate!);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final controller = ref.read(sessionProvider.notifier);
    setState(() => _busy = true);
    try {
      if (!_needsRefresh) {
        await ref
            .read(profileRepositoryProvider)
            .update(
              OwnProfile(
                fullName: _name.text,
                email: widget.profile.email,
                phone: _phone.text,
                address: _address.text,
                birthDate: _birthDate?.toIso8601String().split('T').first,
              ),
            );
        _needsRefresh = true;
      }
      await controller.reload();
      if (mounted) {
        showManagementMessage(context, 'Perfil atualizado.');
        leaveManagementPage(context, '/gestor/perfil');
      }
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          _needsRefresh
              ? 'Perfil salvo. Não foi possível atualizar a sessão; tente atualizar novamente.'
              : 'Não foi possível salvar seu perfil. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: 'Configurações de conta',
    fallbackLocation: '/gestor/perfil',
    busy: _busy,
    child: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('E-mail de acesso', style: AdminStyles.fieldLabel),
                const SizedBox(height: 6),
                SelectableText(widget.profile.email, style: AdminStyles.body),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Dados pessoais', style: AdminStyles.cardTitle),
          const SizedBox(height: 16),
          ManagementField(
            label: 'Nome completo',
            labelAbove: true,
            controller: _name,
            requiredValue: true,
            enabled: !_busy && !_needsRefresh,
          ),
          ManagementField(
            label: 'Telefone',
            labelAbove: true,
            controller: _phone,
            maxLength: 50,
            keyboardType: TextInputType.phone,
            enabled: !_busy && !_needsRefresh,
          ),
          ManagementSelector(
            label: 'Data de nascimento',
            value: _birthDate == null
                ? 'Não informada'
                : formatDate(_birthDate!),
            icon: AppIcons.calendar,
            onPressed: _busy || _needsRefresh
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                      initialDate: _birthDate ?? DateTime(1990),
                      builder: (context, child) => Localizations.override(
                        context: context,
                        locale: const Locale('pt', 'BR'),
                        delegates: GlobalMaterialLocalizations.delegates,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: Theme.of(context).colorScheme.copyWith(
                              primary: AppColors.successDarkGreen,
                            ),
                          ),
                          child: child!,
                        ),
                      ),
                    );
                    if (date != null && mounted) {
                      setState(() => _birthDate = date);
                    }
                  },
          ),
          if (_birthDate != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy || _needsRefresh
                    ? null
                    : () => setState(() => _birthDate = null),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.successDarkGreen,
                  textStyle: AdminStyles.fieldLabel,
                ),
                child: const Text('Limpar data'),
              ),
            ),
          const SizedBox(height: 16),
          ManagementField(
            label: 'Endereço',
            labelAbove: true,
            controller: _address,
            maxLength: 500,
            lines: 2,
            enabled: !_busy && !_needsRefresh,
          ),
          PrimaryButton(
            _busy
                ? 'Salvando...'
                : _needsRefresh
                ? 'Atualizar sessão'
                : 'Salvar perfil',
            compact: true,
            color: AppColors.successDarkGreen,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    ),
  );
}
