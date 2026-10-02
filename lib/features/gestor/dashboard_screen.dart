import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';
import 'widgets.dart';

class GestorDashboardScreen extends ConsumerWidget {
  const GestorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).value?.user;
    final result = ref.watch(gestorDashboardProvider);
    final data = result.asData?.value;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        backgroundColor: AppColors.surface,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.successBg,
                shape: BoxShape.circle,
              ),
              child: Text(
                user?.initials ?? '',
                style: const TextStyle(
                  fontFamily: AppFonts.outfit,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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
                    'Olá, ${user?.fullName.split(' ').first ?? 'Gestor'}',
                    style: const TextStyle(
                      fontFamily: AppFonts.outfit,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const Text(
                    'Gerente de Plataforma',
                    style: TextStyle(
                      fontFamily: AppFonts.inter,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Notificações',
              icon: const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.background,
                child: SvgIcon(
                  AppIcons.bell,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
              ),
              onPressed: () {},
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(gestorDashboardProvider);
          try {
            await ref.read(gestorDashboardProvider.future);
          } catch (_) {
            /* Rendered below. */
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (result.hasError)
              DataErrorCard(
                message: 'Não foi possível carregar o painel.',
                retry: () => ref.invalidate(gestorDashboardProvider),
              ),
            if (result.isLoading) ...[
              for (var i = 0; i < 2; i++) ...[
                const Row(
                  children: [
                    Expanded(child: DataSkeleton()),
                    SizedBox(width: 12),
                    Expanded(child: DataSkeleton()),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              const DataSkeleton(chart: true),
            ],
            if (data != null) ...[
              _metrics(data),
              const SizedBox(height: 20),
              _growth(data.growth),
              const Padding(
                padding: EdgeInsets.only(top: 24, bottom: 12),
                child: Text(
                  'Atividade recente',
                  style: TextStyle(
                    fontFamily: AppFonts.outfit,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              if (data.activities.isEmpty)
                const AppCard(child: Text('Nenhuma atividade recente.')),
              for (final activity in data.activities)
                _ActivityRow(activity: activity),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metrics(GestorDashboard data) {
    final metrics = [
      StatMetric(
        label: 'Total de empresas',
        value: formatCount(data.companyCount),
        delta: '+${formatCount(data.newCompanyCount)} este mês',
        icon: AppIcons.building,
      ),
      StatMetric(
        label: 'Total de usuários',
        value: formatCount(data.userCount),
        icon: AppIcons.groups,
      ),
      StatMetric(
        label: 'Taxa de conclusão',
        value: data.completionPct == null
            ? '—'
            : '${data.completionPct!.toStringAsFixed(1).replaceAll('.', ',')}%',
        icon: AppIcons.checkCircle,
      ),
      StatMetric(
        label: 'Usuários ativos',
        value: formatCount(data.activeUserCount),
        icon: AppIcons.trendUp,
      ),
    ];
    return Column(
      children: [
        for (var start = 0; start < metrics.length; start += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = start; i < start + 2; i++) ...[
                  if (i > start) const SizedBox(width: 12),
                  Expanded(
                    child: _DashboardStatCard(
                      key: ValueKey('gestor-stat-$i'),
                      metric: metrics[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (start == 0) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _growth(List<GrowthMonth> rows) {
    final max = rows.fold<int>(
      1,
      (max, row) => math.max(max, math.max(row.companies, row.users)),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'Crescimento da Empresa / Usuários',
                style: TextStyle(
                  fontFamily: AppFonts.outfit,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Últimos 6 meses',
                style: TextStyle(
                  fontFamily: AppFonts.inter,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            const Text('Sem dados de crescimento.')
          else
            Semantics(
              label: rows
                  .map(
                    (row) =>
                        '${monthLabel(row.month)}: '
                        '${row.companies} empresas, ${row.users} usuários',
                  )
                  .join('; '),
              child: LineChart(
                rows
                    .map(
                      (row) =>
                          MapEntry(monthLabel(row.month), row.companies / max),
                    )
                    .toList(),
                secondaryData: rows
                    .map(
                      (row) => MapEntry(monthLabel(row.month), row.users / max),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 16,
            children: [
              Text(
                'Empresas',
                style: TextStyle(
                  fontFamily: AppFonts.inter,
                  color: AppColors.chartBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Usuários',
                style: TextStyle(
                  fontFamily: AppFonts.inter,
                  color: AppColors.accentTeal,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardStatCard extends StatelessWidget {
  final StatMetric metric;
  const _DashboardStatCard({super.key, required this.metric});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 110),
    child: AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.label,
                  style: const TextStyle(
                    fontFamily: AppFonts.inter,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SvgIcon(metric.icon, size: 16, color: AppColors.successDarkGreen),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            metric.value,
            style: const TextStyle(
              fontFamily: AppFonts.outfit,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (metric.delta != null)
            Text(
              metric.delta!,
              style: const TextStyle(
                fontFamily: AppFonts.inter,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
                height: 1.2,
              ),
            )
          else
            SizedBox(height: MediaQuery.textScalerOf(context).scale(11) * 1.2),
        ],
      ),
    ),
  );
}

class _ActivityRow extends StatelessWidget {
  final PlatformActivity activity;
  const _ActivityRow({required this.activity});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.successBg,
              shape: BoxShape.circle,
            ),
            child: SvgIcon(
              activity.kind == 'company' ? AppIcons.building : AppIcons.book,
              color: AppColors.successDarkGreen,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.kind == 'company'
                      ? '${activity.name} cadastrada'
                      : '${activity.name} atualizou o progresso em ${activity.title}',
                  style: const TextStyle(
                    fontFamily: AppFonts.inter,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _timeAgo(activity.occurredAt),
                  style: const TextStyle(
                    fontFamily: AppFonts.inter,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String _timeAgo(DateTime date) {
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inMinutes < 1) return 'Agora';
    if (elapsed.inHours < 1) return 'Há ${elapsed.inMinutes} min';
    if (elapsed.inDays < 1) return 'Há ${elapsed.inHours} h';
    return 'Há ${elapsed.inDays} ${elapsed.inDays == 1 ? 'dia' : 'dias'}';
  }
}
