import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/company_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../auth/pending_invites.dart';
import '../gestor/widgets.dart' show DataSkeleton;
import 'widgets.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});
  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  int _pendingRevision = 0;
  String _search = '';
  int _offset = 0;
  (String?, String?)? _identity;
  Timer? _debounce;

  EmployeeQuery _query(int offset) =>
      (companyId: _identity!.$2 ?? '', search: _search, offset: offset);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(companyEmployeesProvider);
    ref.invalidate(companyDashboardProvider);
    setState(() {
      _offset = 0;
      _pendingRevision++;
    });
    try {
      await ref.read(companyEmployeesProvider(_query(0)).future);
    } catch (_) {
      /* Rendered below. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(
      sessionProvider.select(
        (state) => (state.value?.user.id, state.value?.active?.companyId),
      ),
    );
    if (_identity != identity) {
      _identity = identity;
      _debounce?.cancel();
      _offset = 0;
      _search = '';
      _pendingRevision++;
    }
    final companyId = identity.$2;
    final queries = [
      for (var offset = 0; offset <= _offset; offset += 50) _query(offset),
    ];
    final pages = [
      for (final query in queries) ref.watch(companyEmployeesProvider(query)),
    ];
    final counts = pages.first.asData?.value;
    final employees = [for (final page in pages) ...?page.asData?.value.items];
    final loading = pages.any((page) => page.isLoading);
    final hasError = pages.any((page) => page.hasError);
    return Theme(
      data: CompanyStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Funcionários cadastrados'),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppColors.successDarkGreen,
          tooltip: 'Convidar funcionário',
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white, width: 2),
          ),
          onPressed: companyId == null
              ? null
              : () async {
                  await context.push('/empresa/employee/add');
                  if (mounted) {
                    await _refresh();
                  }
                },
          child: const SvgIcon(AppIcons.plus, color: Colors.white),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SearchField(
                        'Pesquise por nome, departamento...',
                        key: ValueKey(identity),
                        compact: true,
                        prefixIcon: const SvgIcon(
                          AppIcons.search,
                          size: 18,
                          color: Color(0xFF475569),
                        ),
                        onChanged: (value) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 300),
                            () {
                              if (mounted && _identity == identity) {
                                setState(() {
                                  _search = value.trim();
                                  _offset = 0;
                                });
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              'Todos os funcionários${counts == null ? '' : ' (${counts.totalCount})'}',
                            ),
                            shape: const StadiumBorder(),
                            backgroundColor: AppColors.successBg,
                            side: const BorderSide(
                              color: AppColors.successDarkGreen,
                            ),
                            labelStyle: AdminStyles.fieldLabel.copyWith(
                              fontWeight: FontWeight.w500,
                              color: AppColors.successDarkGreen,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Semantics(
                            enabled: false,
                            label: 'De licença, disponível em breve',
                            child: const Tooltip(
                              message:
                                  'Situação de licença ainda não disponível.',
                              child: Chip(
                                label: Text(
                                  'De licença',
                                  style: CompanyStyles.caption,
                                ),
                                backgroundColor: AppColors.background,
                                side: BorderSide(color: AppColors.border),
                                visualDensity: VisualDensity.compact,
                                shape: StadiumBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var page = 0; page < pages.length; page++)
                        if (pages[page].hasError)
                          CompanyErrorCard(
                            message: 'Não foi possível carregar funcionários.',
                            retry: () => ref.invalidate(
                              companyEmployeesProvider(queries[page]),
                            ),
                          ),
                      if (pages.first.isLoading) ...[
                        const DataSkeleton(),
                        const SizedBox(height: 12),
                        const DataSkeleton(),
                      ],
                      if (counts != null)
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Exibindo ${employees.length} de ${counts.filteredCount} funcionários${_search.isEmpty ? '.' : ' encontrados.'}',
                            style: CompanyStyles.caption,
                          ),
                        ),
                      if (!loading && !hasError && employees.isEmpty)
                        AppCard(
                          child: Text(
                            _search.isEmpty
                                ? 'Nenhum funcionário cadastrado.'
                                : 'Nenhum funcionário encontrado.',
                            style: AdminStyles.body,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: employees.length,
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CompanyEmployeeCard(employee: employees[index]),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (_offset > 0 && pages.last.isLoading)
                        const DataSkeleton(),
                      if (!loading &&
                          !hasError &&
                          counts != null &&
                          employees.length < counts.filteredCount)
                        TextButton(
                          onPressed: () => setState(() => _offset += 50),
                          child: const Text('Carregar mais funcionários'),
                        ),
                    ],
                  ),
                ),
              ),
              if (companyId != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverToBoxAdapter(
                    child: PendingInvitesSection(
                      key: ValueKey((companyId, _pendingRevision)),
                      role: Role.funcionario,
                      companyId: companyId,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompanyEmployeeCard extends StatelessWidget {
  final Employee employee;
  const CompanyEmployeeCard({super.key, required this.employee});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CompanyAvatar(initials: employee.initials, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.fullName,
                    style: AdminStyles.cardTitle.copyWith(fontSize: 16),
                  ),
                  Text(
                    employee.department.isEmpty
                        ? 'Sem departamento'
                        : employee.department,
                    style: CompanyStyles.caption,
                  ),
                ],
              ),
            ),
            if (employee.status != EmployeeStatus.unknown) ...[
              const SizedBox(width: 8),
              CompanyBadge(
                employee.status == EmployeeStatus.active
                    ? 'ATIVO'
                    : 'De licença',
                warning: employee.status == EmployeeStatus.onLeave,
              ),
            ],
          ],
        ),
        const Divider(height: 24),
        ProgressBar(
          employee.hasCompletion ? employee.completionPct / 100 : 0,
          height: 6,
          color: AppColors.successDarkGreen,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                'Progresso de Conclusão',
                style: CompanyStyles.caption.copyWith(
                  color: const Color(0xFF475569),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              employee.hasCompletion
                  ? '${employee.completionPct.round()}%'
                  : 'Sem dados',
              style: CompanyStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.successDarkGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          employee.lastActivityAt == null
              ? 'Nenhuma atividade registrada'
              : 'Última atividade: ${_activityLabel(employee.lastActivityAt!)}',
          style: CompanyStyles.caption,
        ),
      ],
    ),
  );
}

String _activityLabel(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} às ${two(local.hour)}:${two(local.minute)}';
}
