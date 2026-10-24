import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../data/repositories/employee_providers.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';
import 'certificates_section.dart';
import 'widgets.dart';

class EmployeeProgressScreen extends ConsumerWidget {
  const EmployeeProgressScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(employeeSummaryProvider);
    return Theme(
      data: EmployeeStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Meu progresso'),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            refreshLearning(ref);
            try {
              await ref.read(employeeSummaryProvider.future);
            } catch (_) {}
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Acompanhe os cursos concluídos e seus certificados.',
                style: AdminStyles.body,
              ),
              const SizedBox(height: 16),
              EmployeeResult(
                result: summary,
                retry: () => ref.invalidate(employeeSummaryProvider),
                builder: (data) => Column(
                  children: [
                    AppCard(
                      child: Row(
                        children: [
                          DonutChart(
                            data.completion ?? 0,
                            color: AppColors.primary,
                            size: 90,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Taxa de conclusão',
                                  style: AdminStyles.cardTitle,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  data.completion == null
                                      ? 'Nenhum curso disponível'
                                      : '${data.completedCourseCount} de ${data.courseCount} cursos disponíveis concluídos',
                                  style: AdminStyles.body,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader('Cursos em andamento', compact: true),
              const _InProgress(),
              const SectionHeader('Concluído com certificado', compact: true),
              const CertificatesSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _InProgress extends ConsumerStatefulWidget {
  const _InProgress();
  @override
  ConsumerState<_InProgress> createState() => _InProgressState();
}

class _InProgressState extends ConsumerState<_InProgress> {
  int _offset = 0;
  EmployeeScope? _scope;
  LearningQuery _query(int offset) => (
    scope: _scope!,
    search: '',
    kind: null,
    state: 'in_progress',
    offset: offset,
  );
  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(employeeScopeProvider);
    if (scope != _scope) {
      _scope = scope;
      _offset = 0;
    }
    final pages = [
      for (var offset = 0; offset <= _offset; offset += 50)
        ref.watch(learningCatalogProvider(_query(offset))),
    ];
    final items = [for (final page in pages) ...?page.asData?.value.items];
    final total = pages.first.asData?.value.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < pages.length; i++)
          EmployeeResult(
            result: pages[i],
            retry: () =>
                ref.invalidate(learningCatalogProvider(_query(i * 50))),
            builder: (page) => Column(
              children: [
                for (final course in page.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LearningCard(
                      course: course,
                      progressColor: AppColors.successDarkGreen,
                    ),
                  ),
              ],
            ),
          ),
        if (total == 0)
          const AppCard(
            child: Text('Nenhum curso em andamento.', style: AdminStyles.body),
          ),
        if (total != null &&
            items.length < total &&
            pages.last.asData?.value.items.length == 50)
          TextButton(
            onPressed: () => setState(() => _offset += 50),
            child: const Text('Carregar mais cursos'),
          ),
      ],
    );
  }
}
