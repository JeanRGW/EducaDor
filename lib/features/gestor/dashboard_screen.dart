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
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            AvatarBadge(user?.initials ?? ''),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Olá, ${user?.fullName.split(' ').first ?? 'Gestor'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'Gerente de Plataforma',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const IconButton(
              tooltip: 'Notificações',
              icon: SvgIcon(AppIcons.bell),
              onPressed: null,
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
              const SizedBox(height: 16),
              _growth(data.growth),
              const SectionHeader('Atividade recente'),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = start; i < start + 2; i++) ...[
                if (i > start) const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    label: metrics[i].label,
                    value: metrics[i].value,
                    icon: metrics[i].icon,
                    delta: metrics[i].delta,
                  ),
                ),
              ],
            ],
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
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                'Últimos 6 meses',
                style: TextStyle(fontSize: 12, color: AppColors.primary),
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
                style: TextStyle(color: AppColors.chartBlue, fontSize: 12),
              ),
              Text(
                'Usuários',
                style: TextStyle(color: AppColors.accentTeal, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final PlatformActivity activity;
  const _ActivityRow({required this.activity});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.successBg,
              shape: BoxShape.circle,
            ),
            child: SvgIcon(
              activity.kind == 'company' ? AppIcons.building : AppIcons.book,
              color: AppColors.successDarkGreen,
              size: 20,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _timeAgo(activity.occurredAt),
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
