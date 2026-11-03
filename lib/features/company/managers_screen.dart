import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/admin_styles.dart';
import '../auth/pending_invites.dart';
import '../gestor/management_widgets.dart' show leaveManagementPage;
import '../gestor/widgets.dart' show DataSkeleton;
import 'widgets.dart';

class CompanyManagersScreen extends ConsumerStatefulWidget {
  const CompanyManagersScreen({super.key});

  @override
  ConsumerState<CompanyManagersScreen> createState() =>
      _CompanyManagersScreenState();
}

class _CompanyManagersScreenState extends ConsumerState<CompanyManagersScreen> {
  List<User> _people = [];
  bool _loading = false;
  bool _error = false;
  bool _hasMore = false;
  int _offset = 0;
  int _request = 0;
  String _search = '';
  Timer? _debounce;
  int _pendingRevision = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _refresh() {
    _pendingRevision++;
    _load();
  }

  void _searchChanged(String value) {
    _search = value;
    _request++;
    _debounce?.cancel();
    setState(() {
      _people = [];
      _offset = 0;
      _hasMore = false;
      _loading = true;
      _error = false;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _load());
  }

  Future<void> _load({bool more = false}) async {
    _debounce?.cancel();
    final request = ++_request;
    setState(() {
      if (!more) {
        _people = [];
        _offset = 0;
      }
      _loading = true;
      _error = false;
    });
    try {
      final companyId = ref.read(sessionProvider).value!.active!.companyId!;
      final rows = await ref
          .read(peopleRepositoryProvider)
          .companyManagers(companyId, search: _search, offset: _offset);
      if (!mounted || request != _request) return;
      setState(() {
        _people = [..._people, ...rows];
        _offset += rows.length;
        _hasMore = rows.length == 50;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (previous, next) {
      if (previous?.value?.active?.companyId != next.value?.active?.companyId &&
          next.value?.active?.companyId != null) {
        _refresh();
      }
    });
    return Theme(
      data: CompanyStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestores da empresa'),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: () => leaveManagementPage(context, '/empresa/perfil'),
            icon: const SvgIcon(
              AppIcons.arrowBack,
              size: 20,
              color: AppColors.successDarkGreen,
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Convidar gestor da empresa',
          backgroundColor: AppColors.primary,
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white, width: 2),
          ),
          onPressed: () async {
            await context.push('/empresa/manager/add');
            if (mounted) setState(_refresh);
          },
          child: const SvgIcon(AppIcons.plus, color: Colors.white),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SearchField('Pesquisar gestores', onChanged: _searchChanged),
            if (_error)
              CompanyErrorCard(
                message: 'Não foi possível carregar gestores.',
                retry: () => _load(more: _offset > 0),
              ),
            if (_loading && _people.isEmpty) const DataSkeleton(),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Gestores ativos', style: AdminStyles.cardTitle),
            ),
            if (!_loading && !_error && _people.isEmpty)
              const Text('Nenhum gestor encontrado.', style: AdminStyles.body),
            for (final member in _people) ...[
              AppCard(
                child: Row(
                  children: [
                    CompanyAvatar(initials: member.initials, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(member.fullName, style: AdminStyles.cardTitle),
                          Text(member.email, style: CompanyStyles.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_hasMore && !_error)
              TextButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: Text(
                  _loading ? 'Carregando...' : 'Carregar mais gestores',
                ),
              ),
            PendingInvitesSection(
              key: ValueKey(_pendingRevision),
              role: Role.empresa,
              companyId: ref.read(sessionProvider).value!.active!.companyId!,
            ),
          ],
        ),
      ),
    );
  }
}
