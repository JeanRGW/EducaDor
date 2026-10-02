import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';
import 'widgets.dart';

class GestorReportsScreen extends ConsumerStatefulWidget {
  const GestorReportsScreen({super.key});
  @override
  ConsumerState<GestorReportsScreen> createState() =>
      _GestorReportsScreenState();
}

class _GestorReportsScreenState extends ConsumerState<GestorReportsScreen> {
  late ReportPeriod _period;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = (
      from: DateTime(now.year, now.month - 5, 1),
      to: DateTime(now.year, now.month, now.day),
    );
  }

  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _period.from, end: _period.to),
      helpText: 'Selecionar período',
      saveText: 'Confirmar',
      confirmText: 'Confirmar',
      cancelText: 'Cancelar',
      builder: (context, child) => Localizations.override(
        context: context,
        locale: const Locale('pt', 'BR'),
        delegates: GlobalMaterialLocalizations.delegates,
        child: child,
      ),
    );
    if (selected == null || !mounted) return;
    final days =
        DateTime.utc(selected.end.year, selected.end.month, selected.end.day)
            .difference(
              DateTime.utc(
                selected.start.year,
                selected.start.month,
                selected.start.day,
              ),
            )
            .inDays;
    if (days > 365) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um período de até 366 dias.')),
      );
      return;
    }
    setState(() => _period = (from: selected.start, to: selected.end));
  }

  Future<void> _refresh() async {
    ref.invalidate(gestorActivityReportProvider(_period));
    for (var offset = 0; offset <= _offset; offset += 50) {
      ref.invalidate(gestorCompletionProvider(offset));
    }
    setState(() => _offset = 0);
    await Future.wait([
      ref
          .read(gestorActivityReportProvider(_period).future)
          .then<void>((_) {}, onError: (Object _) {}),
      ref
          .read(gestorCompletionProvider(0).future)
          .then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(gestorActivityReportProvider(_period));
    final pages = [
      for (var offset = 0; offset <= _offset; offset += 50)
        ref.watch(gestorCompletionProvider(offset)),
    ];
    final companies = [for (final page in pages) ...?page.asData?.value];
    final data = activity.asData?.value;
    return Theme(
      data: AdminStyles.screenTheme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          toolbarHeight: 52,
          backgroundColor: AppColors.surface,
          titleTextStyle: AdminStyles.pageTitle,
          title: const Text('Relatórios e Análises'),
          actions: const [
            IconButton(
              tooltip: 'Exportar CSV',
              onPressed: null,
              icon: SvgIcon(
                AppIcons.fileDownload,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: AppCard(
                    borderRadius: 8,
                    color: AppColors.background,
                    padding: EdgeInsets.zero,
                    onTap: _pickPeriod,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          const SvgIcon(
                            AppIcons.calendar,
                            size: 16,
                            color: Color(0xFF475569),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${formatDate(_period.from)} - ${formatDate(_period.to)}',
                              style: AdminStyles.fieldText,
                            ),
                          ),
                          const SvgIcon(
                            AppIcons.chevronDown,
                            size: 16,
                            color: Color(0xFF475569),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      if (pages[i].hasError)
                        DataErrorCard(
                          message: 'Não foi possível carregar a conclusão.',
                          retry: () =>
                              ref.invalidate(gestorCompletionProvider(i * 50)),
                        ),
                    if (pages.first.isLoading) const DataSkeleton(chart: true),
                    if (companies.isNotEmpty)
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Conclusão pela Empresa',
                              style: AdminStyles.cardTitle,
                            ),
                            const SizedBox(height: 8),
                            for (final company in companies)
                              if (company.percent != null)
                                ReportBarRow(
                                  company.company,
                                  company.percent!,
                                  compact: true,
                                  color: AppColors.successDarkGreen,
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          company.company,
                                          style: AdminStyles.body.copyWith(
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Sem dados',
                                        style: AdminStyles.emptyState.copyWith(
                                          color: AppColors.textMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    if (companies.isEmpty && pages.first.asData != null)
                      const AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conclusão pela Empresa',
                              style: AdminStyles.cardTitle,
                            ),
                            SizedBox(height: 12),
                            _ReportEmptyState('Nenhuma empresa cadastrada.'),
                          ],
                        ),
                      ),
                    if (_offset > 0 && pages.last.isLoading)
                      const DataSkeleton(),
                    if (pages.last.asData?.value.length == 50)
                      TextButton(
                        onPressed: () => setState(() => _offset += 50),
                        child: const Text('Carregar mais empresas'),
                      ),
                    const SizedBox(height: 16),
                    if (activity.hasError)
                      DataErrorCard(
                        message: 'Não foi possível carregar a atividade.',
                        retry: () => ref.invalidate(
                          gestorActivityReportProvider(_period),
                        ),
                      ),
                    if (activity.isLoading) const DataSkeleton(chart: true),
                    if (data != null)
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Conteúdo mais popular',
                              style: AdminStyles.cardTitle,
                            ),
                            const SizedBox(height: 12),
                            if (data.popularContent.isEmpty)
                              const _ReportEmptyState(
                                'Nenhuma conclusão no período.',
                              ),
                            for (var i = 0; i < data.popularContent.length; i++)
                              _PopularRow(
                                rank: i + 1,
                                entry: data.popularContent[i],
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (activity.isLoading) const DataSkeleton(chart: true),
                    if (data != null) _engagement(data.engagement),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _engagement(List<EngagementMonth> rows) {
    final max = rows.fold<int>(1, (max, row) => math.max(max, row.activeUsers));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Engajamento mensal dos usuários',
            style: AdminStyles.cardTitle,
          ),
          const SizedBox(height: 16),
          rows.every((row) => row.activeUsers == 0)
              ? const _ReportEmptyState('Nenhuma atividade no período.')
              : Semantics(
                  label: rows
                      .map(
                        (row) =>
                            '${monthLabel(row.month)} ${row.month.year}: '
                            '${row.activeUsers} usuários ativos',
                      )
                      .join('; '),
                  child: BarChart(
                    rows
                        .map(
                          (row) => MapEntry(
                            '${monthLabel(row.month)}/${row.month.year % 100}',
                            row.activeUsers / max,
                          ),
                        )
                        .toList(),
                  ),
                ),
        ],
      ),
    );
  }
}

class _ReportEmptyState extends StatelessWidget {
  final String text;
  const _ReportEmptyState(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: AdminStyles.emptyState,
    ),
  );
}

class _PopularRow extends StatelessWidget {
  final int rank;
  final PopularContent entry;
  const _PopularRow({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$rank',
            style: const TextStyle(
              fontFamily: AppFonts.inter,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.successDarkGreen,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: AdminStyles.body.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatCount(entry.completions)} conclusões',
                style: const TextStyle(
                  fontFamily: AppFonts.inter,
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
