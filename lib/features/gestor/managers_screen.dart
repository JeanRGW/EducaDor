import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../auth/pending_invites.dart';
import 'management_widgets.dart';
import 'widgets.dart';

class GestorManagersScreen extends ConsumerStatefulWidget {
  final String? companyId;
  const GestorManagersScreen({super.key, this.companyId});
  @override
  ConsumerState<GestorManagersScreen> createState() =>
      _GestorManagersScreenState();
}

class _GestorManagersScreenState extends ConsumerState<GestorManagersScreen> {
  List<User> _members = [];
  bool _loading = true;
  bool _error = false;
  bool _more = false;
  bool _busy = false;
  int _revision = 0;
  int _request = 0;
  String _search = '';
  Timer? _debounce;
  Future<Company>? _company;
  @override
  void initState() {
    super.initState();
    if (widget.companyId != null) {
      _company = ref.read(companyRepositoryProvider).byId(widget.companyId!);
    }
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await ref
          .read(peopleRepositoryProvider)
          .managers(
            companyId: widget.companyId,
            search: _search,
            offset: append ? _members.length : 0,
          );
      if (!mounted || request != _request) return;
      setState(() {
        _members = [if (append) ..._members, ...rows];
        _more = rows.length == 50;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(User member) async {
    final self = member.id == ref.read(sessionProvider).value?.user.id;
    final platform = widget.companyId == null;
    final confirmed = await confirmManagementAction(
      context,
      title: 'Remover acesso de gestor?',
      message:
          '${member.fullName} perderá somente o acesso de gestor ${platform ? 'da plataforma' : 'desta empresa'}. A conta, os outros perfis e o progresso serão preservados.'
          '${self && platform ? ' Você sairá do perfil de gestor da plataforma.' : ''}',
      action: 'Remover acesso',
    );
    if (!confirmed || !mounted) return;
    final controller = ref.read(sessionProvider.notifier);
    setState(() => _busy = true);
    try {
      await ref
          .read(peopleRepositoryProvider)
          .revokeAccess(member.id, companyId: widget.companyId);
      if (self) {
        controller.discardContext(
          platform ? Role.gestor : Role.empresa,
          widget.companyId,
        );
        final session = await controller.reload();
        if (platform && mounted) {
          context.go(session?.homePath ?? '/contexts');
          return;
        }
      }
      if (!mounted) return;
      showManagementMessage(context, 'Acesso de gestor removido.');
      setState(() => _revision++);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        showManagementMessage(
          context,
          managementError(
            error,
            'Não foi possível remover ou atualizar o acesso. Tente novamente.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    fallbackLocation: widget.companyId == null
        ? '/gestor/perfil'
        : '/gestor/company/${widget.companyId}',
    title: widget.companyId == null
        ? 'Gestores da plataforma'
        : 'Gestores da empresa',
    busy: _busy,
    child: RefreshIndicator(
      onRefresh: () async {
        if (_busy) return;
        setState(() {
          _revision++;
          if (widget.companyId != null) {
            _company = ref
                .read(companyRepositoryProvider)
                .byId(widget.companyId!);
          }
        });
        await _load();
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (widget.companyId == null)
            _inviteButton()
          else
            FutureBuilder<Company>(
              future: _company,
              builder: (context, snapshot) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.hasData) ...[
                    Text(
                      snapshot.data!.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (!snapshot.data!.active)
                      const Text(
                        'Empresa pausada. Reative para enviar convites.',
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (snapshot.hasError)
                    DataErrorCard(
                      message: 'Não foi possível carregar a empresa.',
                      retry: () => setState(
                        () => _company = ref
                            .read(companyRepositoryProvider)
                            .byId(widget.companyId!),
                      ),
                    ),
                  _inviteButton(enabled: snapshot.data?.active == true),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SearchField(
            'Pesquisar nome ou e-mail',
            compact: true,
            onChanged: (value) {
              _search = value.trim();
              _request++;
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => _load(),
              );
            },
          ),
          const SectionHeader('Gestores com acesso'),
          if (_error)
            DataErrorCard(
              message: 'Não foi possível carregar gestores.',
              retry: () => _load(),
            ),
          if (_loading && _members.isEmpty) const DataSkeleton(),
          if (!_loading && !_error && _members.isEmpty)
            const Text('Nenhum gestor encontrado.'),
          for (final member in _members)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(member.email),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _busy || _loading
                            ? null
                            : () => _revoke(member),
                        icon: const SvgIcon(AppIcons.userOff, size: 18),
                        label: const Text('Remover acesso'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_more)
            TextButton(
              onPressed: _loading || _busy ? null : () => _load(append: true),
              child: Text(
                _loading ? 'Carregando...' : 'Carregar mais gestores',
              ),
            ),
          PendingInvitesSection(
            key: ValueKey(_revision),
            role: widget.companyId == null ? Role.gestor : Role.empresa,
            companyId: widget.companyId,
          ),
        ],
      ),
    ),
  );

  Widget _inviteButton({bool enabled = true}) => PrimaryButton(
    'Convidar gestor',
    compact: true,
    onPressed: _busy || !enabled
        ? null
        : () async {
            await context.push(
              widget.companyId == null
                  ? '/gestor/manager/add'
                  : '/gestor/company/${widget.companyId}/manager/add',
            );
            if (mounted) {
              setState(() => _revision++);
              await _load();
            }
          },
  );
}
