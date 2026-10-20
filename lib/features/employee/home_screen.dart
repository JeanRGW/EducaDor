import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../data/repositories/employee_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/common.dart';
import '../company/widgets.dart' show CompanyAvatar;
import 'widgets.dart';

class EmployeeHomeScreen extends ConsumerWidget {
  const EmployeeHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final scope = ref.watch(employeeScopeProvider);
    final continuingQuery = (
      scope: scope,
      search: '',
      kind: null,
      state: 'in_progress',
      offset: 0,
    );
    final recommendedQuery = (
      scope: scope,
      search: '',
      kind: null,
      state: 'not_started',
      offset: 0,
    );
    final summary = ref.watch(employeeSummaryProvider);
    final continuing = ref.watch(learningCatalogProvider(continuingQuery));
    final recommended = ref.watch(learningCatalogProvider(recommendedQuery));
    return Theme(
      data: EmployeeStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: MediaQuery.textScalerOf(context).scale(16) > 22
              ? 100
              : 78,
          title: Row(
            children: [
              CompanyAvatar(initials: session?.user.initials ?? ''),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Olá, ${session?.user.fullName.trim().split(' ').first ?? 'você'}!',
                      style: AdminStyles.formTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      session?.active?.companyName ?? '',
                      style: AdminStyles.fieldLabel.copyWith(
                        color: AppColors.successDarkGreen,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
              EmployeeResult(
                result: summary,
                retry: () => ref.invalidate(employeeSummaryProvider),
                builder: (data) => AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          const Text(
                            'Seu progresso de aprendizado',
                            style: AdminStyles.cardTitle,
                          ),
                          Text(
                            data.completion == null
                                ? 'Sem cursos disponíveis'
                                : '${(data.completion! * 100).round()}% concluído',
                            style: AdminStyles.fieldLabel.copyWith(
                              color: AppColors.successDarkGreen,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ProgressBar(
                        data.completion ?? 0,
                        color: AppColors.successDarkGreen,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${data.completedCourseCount} de ${data.courseCount} cursos disponíveis concluídos',
                        style: AdminStyles.body,
                      ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Continue aprendendo', compact: true),
              EmployeeResult(
                result: continuing,
                retry: () =>
                    ref.invalidate(learningCatalogProvider(continuingQuery)),
                builder: (page) => page.items.isEmpty
                    ? const AppCard(
                        child: Text(
                          'Escolha um curso para começar.',
                          style: AdminStyles.body,
                        ),
                      )
                    : LearningCard(course: page.items.first),
              ),
              SectionHeader(
                'Recomendado para você',
                compact: true,
                action: 'Ver tudo',
                onAction: () => context.go('/funcionario/modulos'),
              ),
              EmployeeResult(
                result: recommended,
                retry: () =>
                    ref.invalidate(learningCatalogProvider(recommendedQuery)),
                builder: (page) => page.items.isEmpty
                    ? const AppCard(
                        child: Text(
                          'Nenhum novo curso disponível no momento.',
                          style: AdminStyles.body,
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final cards = page.items
                              .take(2)
                              .map(
                                (course) =>
                                    LearningCard(course: course, compact: true),
                              )
                              .toList();
                          if (constraints.maxWidth < 350 ||
                              MediaQuery.textScalerOf(context).scale(13) > 18) {
                            return Column(
                              children: [
                                for (final card in cards)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: card,
                                  ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                if (i > 0) const SizedBox(width: 12),
                                Expanded(child: cards[i]),
                              ],
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
