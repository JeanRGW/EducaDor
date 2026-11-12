import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/company_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';
import '../gestor/widgets.dart' show DataSkeleton;
import '../reports/csv_export.dart';
import 'widgets.dart';

class CompanyCompletionScreen extends ConsumerStatefulWidget {
  const CompanyCompletionScreen({super.key});
  @override
  ConsumerState<CompanyCompletionScreen> createState() =>
      _CompanyCompletionScreenState();
}

class _CompanyCompletionScreenState
    extends ConsumerState<CompanyCompletionScreen> {
  int _lastPage = 0;
  String? _companyId;
  bool _exporting = false;

  Future<void> _export() async {
    final session = ref.read(sessionProvider).value;
    final companyId = session?.active?.companyId;
    if (session == null ||
        session.active?.role != Role.empresa ||
        companyId == null ||
        session.needsMfa ||
        session.needsPassword) {
      return;
    }
    var valid = true;
    final router = GoRouter.maybeOf(context);
    const reportPath = '/empresa/relatorios';
    void routeChanged() {
      if (router?.routerDelegate.currentConfiguration.uri.path != reportPath) {
        valid = false;
      }
    }

    router?.routerDelegate.addListener(routeChanged);
    if (router != null) routeChanged();
    final subscription = ref.listenManual(sessionProvider, (previous, next) {
      if (next.value?.user.id != session.user.id ||
          next.value?.needsMfa == true ||
          next.value?.needsPassword == true ||
          next.value?.active?.role != Role.empresa ||
          next.value?.active?.companyId != companyId) {
        valid = false;
      }
    });
    bool current() => valid && mounted;
    setState(() => _exporting = true);
    try {
      final repository = ref.read(employeeRepositoryProvider);
      if (!current()) return;
      final page = await repository.page(companyId);
      if (!mounted || !valid) return;
      final employees = requireSingleSnapshot(
        page.items,
        total: page.filteredCount,
      );
      if (employees.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum funcionário para exportar.')),
        );
        return;
      }
      final rows = <List<String>>[
        ['Funcionário', 'Departamento', 'Cargo', 'Conclusão (%)'],
        for (final employee in employees)
          [
            employee.fullName,
            employee.department,
            employee.jobTitle,
            employee.hasCompletion
                ? employee.completionPct.toString().replaceAll('.', ',')
                : 'Sem dados',
          ],
      ];
      await saveCsv(
        reportFilename('conclusao-funcionarios', DateTime.now()),
        encodeCsv(rows),
      );
    } on ExportTooLarge {
      if (mounted && valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Exportação indisponível para mais de 50 funcionários: não é possível garantir um retrato consistente.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível exportar os dados. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      subscription.close();
      router?.routerDelegate.removeListener(routeChanged);
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyId = ref.watch(sessionProvider).value?.active?.companyId ?? '';
    if (companyId != _companyId) {
      _companyId = companyId;
      _lastPage = 0;
    }
    final pages = [
      for (var page = 0; page <= _lastPage; page++)
        ref.watch(
          companyDepartmentsProvider((companyId: companyId, offset: page * 50)),
        ),
    ];
    final departments = [for (final page in pages) ...?page.asData?.value];
    final hasError = pages.any((page) => page.hasError);
    final loading = pages.any((page) => page.isLoading);
    return Theme(
      data: CompanyStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Relatórios'),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            for (var page = 0; page <= _lastPage; page++) {
              ref.invalidate(
                companyDepartmentsProvider((
                  companyId: companyId,
                  offset: page * 50,
                )),
              );
            }
            setState(() => _lastPage = 0);
            try {
              await ref.read(
                companyDepartmentsProvider((
                  companyId: companyId,
                  offset: 0,
                )).future,
              );
            } catch (_) {
              /* Shown below. */
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Conclusão atual · sem filtro de período',
                          style: AdminStyles.fieldLabel(context),
                        ),
                      ),
                      SizedBox(width: 8),
                      SvgIcon(
                        AppIcons.calendar,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Conclusão por departamento',
                            style: AdminStyles.cardTitle(context),
                          ),
                          const SizedBox(height: 10),
                          for (final department in departments)
                            if (department.value != null)
                              ReportBarRow(
                                department.key,
                                department.value!,
                                compact: true,
                                color: AppColors.primary,
                                valueColor: AppColors.primary,
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  '${department.key}: sem dados de conclusão',
                                  style: AdminStyles.body(context),
                                ),
                              ),
                          if (loading) const DataSkeleton(),
                          if (hasError)
                            CompanyErrorCard(
                              message:
                                  'Não foi possível carregar a conclusão por departamento.',
                              retry: () {
                                for (var page = 0; page <= _lastPage; page++) {
                                  if (pages[page].hasError) {
                                    ref.invalidate(
                                      companyDepartmentsProvider((
                                        companyId: companyId,
                                        offset: page * 50,
                                      )),
                                    );
                                  }
                                }
                              },
                            ),
                          if (!loading && !hasError && departments.isEmpty)
                            Text(
                              'Nenhum dado de conclusão por departamento.',
                              style: AdminStyles.body(context),
                            ),
                          if (!loading &&
                              !hasError &&
                              pages.last.asData?.value.length == 50)
                            TextButton(
                              onPressed: () => setState(() => _lastPage++),
                              child: const Text('Carregar mais departamentos'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Indicadores Regulatórios',
                            style: AdminStyles.cardTitle(context),
                          ),
                          SizedBox(height: 12),
                          _Indicator(
                            'Funcionários com desempenho insuficiente',
                            highlighted: true,
                          ),
                          SizedBox(height: 8),
                          _Indicator('Certificados aguardando renovação'),
                          SizedBox(height: 8),
                          Text(
                            'Indicadores disponíveis em breve.',
                            style: CompanyStyles.caption(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final buttons = [
                          const Tooltip(
                            message: 'Exportação em PDF disponível em breve.',
                            child: OutlinedButton(
                              onPressed: null,
                              child: Text('Exportar relatório em PDF'),
                            ),
                          ),
                          FilledButton(
                            onPressed: _exporting ? null : _export,
                            child: Text(
                              _exporting
                                  ? 'Exportando CSV...'
                                  : 'Exportar dados em CSV',
                            ),
                          ),
                        ];
                        if (constraints.maxWidth < 380 ||
                            MediaQuery.textScalerOf(context).scale(12) > 16) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              buttons[0],
                              const SizedBox(height: 8),
                              buttons[1],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: buttons[0]),
                            const SizedBox(width: 12),
                            Expanded(child: buttons[1]),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'O CSV contém a conclusão atual dos funcionários desta empresa.',
                      style: CompanyStyles.caption(context),
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

class _Indicator extends StatelessWidget {
  final String label;
  final bool highlighted;
  const _Indicator(this.label, {this.highlighted = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: highlighted
          ? context.successSurface
          : Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AdminStyles.body(context).copyWith(
              color: highlighted
                  ? context.successForeground
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('—', style: AdminStyles.cardTitle(context)),
      ],
    ),
  );
}
