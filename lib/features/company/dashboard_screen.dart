import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/repositories/company_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/charts.dart';
import '../gestor/widgets.dart' show DataSkeleton;
import '../notifications/notification_settings_sheet.dart';
import 'widgets.dart';

class CompanyDashboardScreen extends ConsumerWidget {
  const CompanyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyName =
        ref.watch(sessionProvider).value?.active?.companyName ?? 'Empresa';
    final result = ref.watch(companyDashboardProvider);
    final data = result.asData?.value;
    final highlights = data?.highlights ?? [];
    final participationMax =
        data?.engagement.fold<int>(
          1,
          (maximum, month) => math.max(maximum, month.activeUsers),
        ) ??
        1;
    return Theme(
      data: CompanyStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: MediaQuery.textScalerOf(context).scale(16) > 22
              ? 100
              : 78,
          shape: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          title: Row(
            children: [
              CompanyAvatar(initials: companyInitials(companyName)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdminStyles.cardTitle(
                        context,
                      ).copyWith(fontSize: 16),
                    ),
                    Text(
                      'Administrador da Empresa',
                      maxLines: 2,
                      style: AdminStyles.body(context).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Notificações',
                onPressed: () => showNotificationSettings(context),
                icon: CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  child: SvgIcon(
                    AppIcons.bell,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(companyDashboardProvider);
            try {
              await ref.read(companyDashboardProvider.future);
            } catch (_) {
              /* Rendered below. */
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (result.hasError) ...[
                CompanyErrorCard(
                  message:
                      'Não foi possível carregar todos os dados do painel.',
                  retry: () => ref.invalidate(companyDashboardProvider),
                ),
                const SizedBox(height: 12),
              ],
              for (var row = 0; row < 2; row++) ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: row == 0
                        ? [
                            Expanded(
                              child: _Metric(
                                label: 'Total de funcionários',
                                value: data == null
                                    ? '—'
                                    : '${data.employeeCount}',
                                caption: data == null
                                    ? 'Sem dados'
                                    : 'Cadastrados',
                                icon: AppIcons.employees,
                                loading: result.isLoading,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Metric(
                                label: 'Cursos ativos',
                                value: data == null
                                    ? '—'
                                    : '${data.activeCourseCount}',
                                caption: data == null
                                    ? 'Sem dados'
                                    : 'Disponíveis para a empresa',
                                icon: AppIcons.book,
                                loading: result.isLoading,
                              ),
                            ),
                          ]
                        : [
                            Expanded(
                              child: _Metric(
                                label: 'Média de conclusão',
                                value: data?.completionPct == null
                                    ? '—'
                                    : '${data!.completionPct!.toStringAsFixed(1).replaceAll('.', ',')}%',
                                caption: data?.completionPct == null
                                    ? 'Sem dados de conclusão'
                                    : 'Conclusão atual',
                                icon: AppIcons.checkCircle,
                                loading: result.isLoading,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Metric(
                                label: 'Certificados',
                                value: data == null
                                    ? '—'
                                    : '${data.certificateCount}',
                                caption: data == null
                                    ? 'Sem dados'
                                    : 'Emitidos nesta empresa',
                                icon: AppIcons.key,
                                loading: result.isLoading,
                              ),
                            ),
                          ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Participação Mensal',
                          style: AdminStyles.cardTitle(context),
                        ),
                        Text(
                          'Tendência de engajamento',
                          style: TextStyle(
                            fontFamily: AppFonts.inter,
                            fontSize: 11,
                            color: context.colors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (result.isLoading)
                      SizedBox(
                        height: 140,
                        child: ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                        ),
                      )
                    else if (data == null)
                      Text(
                        'Participação indisponível.',
                        style: AdminStyles.body(context),
                      )
                    else
                      Semantics(
                        label:
                            'Participação mensal: ${data.engagement.map((month) => '${_monthLabel(month.month)}: ${month.activeUsers} funcionários').join(', ')}',
                        child: ExcludeSemantics(
                          child: LineChart([
                            for (final month in data.engagement)
                              MapEntry(
                                _monthLabel(month.month),
                                month.activeUsers / participationMax,
                              ),
                          ], height: 140),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Funcionários com atualização de progresso por mês. Baseado na última atualização; mês atual parcial.',
                      style: CompanyStyles.caption(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 20, bottom: 12),
                child: Text('Destaques', style: AdminStyles.cardTitle(context)),
              ),
              if (result.isLoading)
                const DataSkeleton()
              else if (result.hasError)
                Text(
                  'Destaques indisponíveis.',
                  style: AdminStyles.body(context),
                )
              else if (highlights.isEmpty)
                AppCard(
                  child: Text(
                    'Nenhuma conclusão registrada na empresa.',
                    style: AdminStyles.body(context),
                  ),
                )
              else ...[
                for (final employee in highlights.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CompanyAvatar(initials: employee.initials, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${employee.fullName}${employee.department.isEmpty ? '' : ' (${employee.department})'}',
                                  style: AdminStyles.body(context).copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  'Conclusão atual',
                                  style: CompanyStyles.caption(context),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          CompanyBadge('${employee.completionPct.round()}%'),
                        ],
                      ),
                    ),
                  ),
                Text(
                  'Maiores conclusões entre todos os funcionários da empresa.',
                  style: CompanyStyles.caption(context),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/empresa/funcionarios'),
                child: const Text('Ver funcionários'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _monthLabel(DateTime date) {
  const months = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];
  return months[date.month - 1];
}

class _Metric extends StatelessWidget {
  final String label, value, caption, icon;
  final bool loading;
  const _Metric({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 110),
    child: loading
        ? const DataSkeleton()
        : AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: AdminStyles.fieldLabel(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SvgIcon(icon, size: 16, color: context.successForeground),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: AppFonts.outfit,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  caption,
                  style: CompanyStyles.caption(context).copyWith(
                    color:
                        caption == 'Em breve' || caption.startsWith('Sem dados')
                        ? Theme.of(context).colorScheme.outline
                        : context.successForeground,
                  ),
                ),
              ],
            ),
          ),
  );
}
