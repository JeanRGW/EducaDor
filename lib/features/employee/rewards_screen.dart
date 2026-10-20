import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/employee_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../gestor/widgets.dart' show DataSkeleton, DataErrorCard;
import 'certificates_section.dart';
import 'widgets.dart';

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});
  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  int _offset = 0;
  String? _busy;
  bool _uncertain = false;
  EmployeeScope? _scope;
  Future<void> _redeem(RedeemableReward reward) async {
    if (_busy != null) return;
    final scope = ref.read(employeeScopeProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resgatar recompensa?'),
        content: Text(
          '${reward.title}\nCusto: ${reward.cost} pontos. O saldo será descontado nesta empresa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resgatar'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        ref.read(employeeScopeProvider) != scope) {
      return;
    }
    setState(() => _busy = reward.id);
    try {
      await ref
          .read(employeeLearningRepositoryProvider)
          .redeem(scope.companyId, reward.id);
      if (mounted && ref.read(employeeScopeProvider) == scope) {
        refreshLearning(ref);
        employeeMessage(context, 'Recompensa resgatada.');
      }
    } on ManagementException catch (error) {
      if (mounted) employeeMessage(context, error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _uncertain = true);
        employeeMessage(
          context,
          'Não foi possível confirmar o resgate. Atualize o saldo antes de tentar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(employeeScopeProvider);
    if (scope != _scope) {
      _scope = scope;
      _offset = 0;
      _uncertain = false;
    }
    final summary = ref.watch(employeeSummaryProvider);
    final pages = [
      for (var offset = 0; offset <= _offset; offset += 50)
        ref.watch(employeeRewardsProvider((scope: scope, offset: offset))),
    ];
    final rewards = [for (final page in pages) ...?page.asData?.value];
    final ranking = ref.watch(employeeRankingProvider);
    final balance = summary.asData?.value.balance;
    return Theme(
      data: EmployeeStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Recompensas e Certificados'),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            refreshLearning(ref);
            ref.invalidate(employeeRewardsProvider);
            setState(() {
              _offset = 0;
              _uncertain = false;
            });
            try {
              await ref.read(employeeSummaryProvider.future);
            } catch (_) {}
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EmployeeResult(
                        result: summary,
                        retry: () => ref.invalidate(employeeSummaryProvider),
                        builder: (data) => Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                              colors: [
                                AppColors.primary,
                                AppColors.successDarkGreen,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SALDO DISPONÍVEL',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Suas conquistas\nviram recompensas',
                                      style: TextStyle(
                                        fontFamily: AppFonts.outfit,
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Semantics(
                                  label: '${data.balance} pontos disponíveis',
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _points(data.balance),
                                        style: AdminStyles.pageTitle.copyWith(
                                          color: Colors.white,
                                          fontSize: 28,
                                        ),
                                      ),
                                      const Text(
                                        'Pontos',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SectionHeader(
                        'Seus certificados conquistados',
                        compact: true,
                      ),
                      const SizedBox(height: 8),
                      const CertificatesSection(compact: true),
                      const SectionHeader('Resgatar item', compact: true),
                      for (var i = 0; i < pages.length; i++)
                        if (pages[i].hasError)
                          DataErrorCard(
                            message: 'Não foi possível carregar recompensas.',
                            retry: () => ref.invalidate(
                              employeeRewardsProvider((
                                scope: scope,
                                offset: i * 50,
                              )),
                            ),
                          ),
                      if (pages.first.isLoading) const DataSkeleton(),
                      if (rewards.isEmpty && pages.first.asData != null)
                        const AppCard(
                          child: Text(
                            'Nenhuma recompensa disponível.',
                            style: AdminStyles.body,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.crossAxisExtent < 360 ||
                            MediaQuery.textScalerOf(context).scale(13) > 18
                        ? 1
                        : constraints.crossAxisExtent > 900
                        ? 4
                        : 2;
                    return SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent:
                            MediaQuery.textScalerOf(context).scale(13) > 18
                            ? 280
                            : 198,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: rewards.length,
                      itemBuilder: (_, index) {
                        final reward = rewards[index];
                        return AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors:
                                        reward.title.toLowerCase().contains(
                                          'caneca',
                                        )
                                        ? [
                                            const Color(0xFFF1F5F9),
                                            const Color(0xFFE2E8F0),
                                          ]
                                        : [
                                            const Color(0xFFCCFBF1),
                                            const Color(0xFFE0E7FF),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SvgIcon(
                                  reward.title.toLowerCase().contains('caneca')
                                      ? AppIcons.coffee
                                      : AppIcons.gift,
                                  size: 40,
                                  color: AppColors.successDarkGreen,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Text(
                                  reward.title,
                                  style: AdminStyles.cardTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${_points(reward.cost)} pontos',
                                style: AdminStyles.fieldLabel.copyWith(
                                  color: AppColors.successDarkGreen,
                                ),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 32),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  backgroundColor: AppColors.successBgSoft,
                                  foregroundColor: AppColors.successDarkGreen,
                                  textStyle: AdminStyles.fieldLabel,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed:
                                    _uncertain ||
                                        _busy != null ||
                                        balance == null ||
                                        balance < reward.cost
                                    ? null
                                    : () => _redeem(reward),
                                child: Text(
                                  _busy == reward.id
                                      ? 'Resgatando...'
                                      : balance != null && balance < reward.cost
                                      ? 'Saldo insuficiente'
                                      : 'Resgatar',
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_offset > 0 && pages.last.isLoading)
                        const DataSkeleton(),
                      if (pages.last.asData?.value.length == 50)
                        TextButton(
                          onPressed: () => setState(() => _offset += 50),
                          child: const Text('Carregar mais recompensas'),
                        ),
                      const SectionHeader(
                        'Ranking da Empresa (Top 3)',
                        compact: true,
                      ),
                      EmployeeResult(
                        result: ranking,
                        retry: () => ref.invalidate(employeeRankingProvider),
                        builder: (rows) => Column(
                          children: [
                            for (var i = 0; i < rows.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: AppCard(
                                  key: ValueKey('rank-${rows[i].userId}'),
                                  color: rows[i].userId == scope.userId
                                      ? AppColors.successBgSoft
                                      : null,
                                  borderRadius: 8,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${i + 1}.',
                                        style: AdminStyles.body.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight:
                                              rows[i].userId == scope.userId
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          '${rows[i].name}${rows[i].department.isEmpty ? '' : ' (${rows[i].department})'}${rows[i].userId == scope.userId ? ' · você' : ''}',
                                          style: AdminStyles.body.copyWith(
                                            color: AppColors.textPrimary,
                                            fontWeight:
                                                rows[i].userId == scope.userId
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${_points(rows[i].points)} pts',
                                        style: AdminStyles.fieldLabel.copyWith(
                                          color: AppColors.successDarkGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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

String _points(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]}.',
);
