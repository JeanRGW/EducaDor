import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../reports/csv_export.dart';
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
  bool _exporting = false;

  Future<void> _export() async {
    final session = ref.read(sessionProvider).value;
    if (session == null ||
        session.active?.role != Role.gestor ||
        session.needsMfa ||
        session.needsPassword) {
      return;
    }
    final period = _period;
    var valid = true;
    final router = GoRouter.maybeOf(context);
    const reportPath = '/gestor/relatorios';
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
          next.value?.active?.role != Role.gestor ||
          next.value?.active?.companyId != session.active?.companyId) {
        valid = false;
      }
    });
    bool current() => valid && mounted;
    setState(() => _exporting = true);
    try {
      final repository = ref.read(reportRepositoryProvider);
      if (!current()) return;
      final companies = requireSingleSnapshot(
        await repository.platformCompletion(),
      );
      if (!current()) return;
      final activity = await repository.platformActivity(
        from: period.from,
        to: period.to,
      );
      if (!current()) return;
      final rows = <List<String>>[
        ['Relatório', 'Período inicial', 'Período final', 'Nome', 'Valor'],
        for (final company in companies)
          [
            'Conclusão atual por empresa',
            '',
            '',
            company.company,
            company.percent?.toString().replaceAll('.', ',') ?? 'Sem dados',
          ],
        for (final entry in activity.popularContent)
          [
            'Conteúdo mais popular (top 10)',
            formatDate(period.from),
            formatDate(period.to),
            entry.title,
            entry.completions.toString(),
          ],
        for (final entry in activity.engagement)
          [
            'Usuários ativos por mês',
            formatDate(period.from),
            formatDate(period.to),
            '${entry.month.month.toString().padLeft(2, '0')}/${entry.month.year}',
            entry.activeUsers.toString(),
          ],
      ];
      await saveCsv(
        reportFilename('relatorio-gestor', DateTime.now()),
        encodeCsv(rows),
      );
    } on ExportTooLarge {
      if (mounted && valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Exportação indisponível com 50 empresas ou mais: não é possível garantir um retrato consistente.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível exportar o relatório. Tente novamente.',
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
    if (selected == null || !mounted || _exporting) return;
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
          backgroundColor: Theme.of(context).colorScheme.surface,
          titleTextStyle: AdminStyles.pageTitle(context),
          title: const Text('Relatórios e Análises'),
          actions: [
            IconButton(
              tooltip: _exporting ? 'Exportando CSV' : 'Exportar CSV',
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : SvgIcon(
                      AppIcons.fileDownload,
                      size: 20,
                      color: Theme.of(context).colorScheme.outline,
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
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: AppCard(
                    borderRadius: 8,
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: EdgeInsets.zero,
                    onTap: _exporting ? null : _pickPeriod,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          SvgIcon(
                            AppIcons.calendar,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${formatDate(_period.from)} - ${formatDate(_period.to)}',
                              style: AdminStyles.fieldText(context),
                            ),
                          ),
                          SvgIcon(
                            AppIcons.chevronDown,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'O CSV inclui a conclusão atual e a atividade do período selecionado, consultadas em momentos distintos.',
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
                            Text(
                              'Conclusão pela Empresa',
                              style: AdminStyles.cardTitle(context),
                            ),
                            const SizedBox(height: 8),
                            for (final company in companies)
                              if (company.percent != null)
                                ReportBarRow(
                                  company.company,
                                  company.percent!,
                                  compact: true,
                                  color: AppColors.primary,
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
                                          style: AdminStyles.body(
                                            context,
                                          ).copyWith(fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Sem dados',
                                        style: AdminStyles.emptyState(context)
                                            .copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outline,
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
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conclusão pela Empresa',
                              style: AdminStyles.cardTitle(context),
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
                            Text(
                              'Conteúdo mais popular',
                              style: AdminStyles.cardTitle(context),
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
          Text(
            'Engajamento mensal dos usuários',
            style: AdminStyles.cardTitle(context),
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
      style: AdminStyles.emptyState(context),
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
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$rank',
            style: const TextStyle(
              fontFamily: AppFonts.inter,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
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
                style: AdminStyles.body(
                  context,
                ).copyWith(color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatCount(entry.completions)} conclusões',
                style: TextStyle(
                  fontFamily: AppFonts.inter,
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
