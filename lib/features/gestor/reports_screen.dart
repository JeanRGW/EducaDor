import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../shared/widgets/app_icons.dart';
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
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('Relatórios e Análises'),
        actions: const [
          IconButton(
            tooltip: 'Exportar CSV',
            onPressed: null,
            icon: SvgIcon(AppIcons.download, color: AppColors.textMuted),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              padding: EdgeInsets.zero,
              onTap: _pickPeriod,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const SvgIcon(
                      AppIcons.calendar,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${formatDate(_period.from)} - ${formatDate(_period.to)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SvgIcon(
                      AppIcons.chevronDown,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const SectionHeader('Conclusão pela Empresa'),
            for (var i = 0; i < pages.length; i++)
              if (pages[i].hasError)
                DataErrorCard(
                  message: 'Não foi possível carregar a conclusão.',
                  retry: () => ref.invalidate(gestorCompletionProvider(i * 50)),
                ),
            if (pages.first.isLoading) const DataSkeleton(chart: true),
            if (companies.isNotEmpty)
              AppCard(
                child: Column(
                  children: [
                    for (final company in companies)
                      if (company.percent != null)
                        ReportBarRow(company.company, company.percent!)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(child: Text(company.company)),
                              const Text('Sem dados'),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            if (companies.isEmpty && pages.first.asData != null)
              const AppCard(child: Text('Nenhuma empresa cadastrada.')),
            if (_offset > 0 && pages.last.isLoading) const DataSkeleton(),
            if (pages.last.asData?.value.length == 50)
              TextButton(
                onPressed: () => setState(() => _offset += 50),
                child: const Text('Carregar mais empresas'),
              ),
            const SizedBox(height: 12),
            const SectionHeader('Conteúdo mais popular'),
            if (activity.hasError)
              DataErrorCard(
                message: 'Não foi possível carregar a atividade.',
                retry: () =>
                    ref.invalidate(gestorActivityReportProvider(_period)),
              ),
            if (activity.isLoading) const DataSkeleton(chart: true),
            if (data != null)
              AppCard(
                child: Column(
                  children: [
                    if (data.popularContent.isEmpty)
                      const Text('Nenhuma conclusão no período.'),
                    for (var i = 0; i < data.popularContent.length; i++)
                      _PopularRow(rank: i + 1, entry: data.popularContent[i]),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const SectionHeader('Engajamento mensal dos usuários'),
            if (activity.isLoading) const DataSkeleton(chart: true),
            if (data != null) _engagement(data.engagement),
          ],
        ),
      ),
    );
  }

  Widget _engagement(List<EngagementMonth> rows) {
    final max = rows.fold<int>(1, (max, row) => math.max(max, row.activeUsers));
    return AppCard(
      child: rows.every((row) => row.activeUsers == 0)
          ? const Center(
              child: Text(
                'Nenhuma atividade no período.',
                textAlign: TextAlign.center,
              ),
            )
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
    );
  }
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
        SizedBox(
          width: 30,
          child: Text(
            '$rank.',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatCount(entry.completions)} conclusões',
                style: const TextStyle(
                  fontSize: 12,
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
