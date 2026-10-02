import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/repositories/company_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';
import '../gestor/widgets.dart' show DataSkeleton;
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
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Conclusão atual · sem filtro de período',
                          style: AdminStyles.fieldLabel,
                        ),
                      ),
                      SizedBox(width: 8),
                      SvgIcon(
                        AppIcons.calendar,
                        size: 16,
                        color: Color(0xFF475569),
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
                          const Text(
                            'Conclusão por departamento',
                            style: AdminStyles.cardTitle,
                          ),
                          const SizedBox(height: 10),
                          for (final department in departments)
                            if (department.value != null)
                              ReportBarRow(
                                department.key,
                                department.value!,
                                compact: true,
                                color: AppColors.successDarkGreen,
                                valueColor: AppColors.successDarkGreen,
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  '${department.key}: sem dados de conclusão',
                                  style: AdminStyles.body,
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
                            const Text(
                              'Nenhum dado de conclusão por departamento.',
                              style: AdminStyles.body,
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
                    const AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Indicadores Regulatórios',
                            style: AdminStyles.cardTitle,
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
                            style: CompanyStyles.caption,
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
                          const Tooltip(
                            message: 'Exportação em CSV disponível em breve.',
                            child: FilledButton(
                              onPressed: null,
                              child: Text('Exportar dados em CSV'),
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
                    const Text(
                      'Exportações disponíveis em breve.',
                      style: CompanyStyles.caption,
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
      color: highlighted ? AppColors.successBg : AppColors.background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AdminStyles.body.copyWith(
              color: highlighted
                  ? AppColors.successDarkGreen
                  : const Color(0xFF475569),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('—', style: AdminStyles.cardTitle),
      ],
    ),
  );
}
