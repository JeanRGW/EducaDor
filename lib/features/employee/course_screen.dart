import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../data/repositories/employee_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../data/models/models.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../gestor/management_widgets.dart' show leaveManagementPage;
import '../gestor/widgets.dart' show DataSkeleton, DataErrorCard;
import 'widgets.dart';

class CourseDetailScreen extends ConsumerWidget {
  final String courseId;
  const CourseDetailScreen({super.key, required this.courseId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(employeeScopeProvider);
    return _Course(
      key: ValueKey((scope, courseId)),
      courseId: courseId,
      scope: scope,
    );
  }
}

class _Course extends ConsumerStatefulWidget {
  final String courseId;
  final EmployeeScope scope;
  const _Course({super.key, required this.courseId, required this.scope});
  @override
  ConsumerState<_Course> createState() => _CourseState();
}

class _CourseState extends ConsumerState<_Course> {
  int _offset = 0;
  bool _issuing = false;
  LessonQuery _query(int offset) =>
      (scope: widget.scope, courseId: widget.courseId, offset: offset);
  void _refresh() {
    ref.invalidate(employeeCourseProvider(widget.courseId));
    ref.invalidate(employeeLessonsProvider);
    refreshLearning(ref);
    setState(() => _offset = 0);
  }

  Future<void> _issue() async {
    final scope = ref.read(employeeScopeProvider);
    setState(() => _issuing = true);
    try {
      await ref
          .read(employeeLearningRepositoryProvider)
          .issueCertificate(scope.companyId, widget.courseId);
      if (mounted && ref.read(employeeScopeProvider) == scope) {
        refreshLearning(ref);
        employeeMessage(
          context,
          'Certificado emitido. Disponível em Recompensas.',
        );
      }
    } catch (_) {
      if (mounted) {
        employeeMessage(
          context,
          'Não foi possível emitir. Conclua todas as aulas e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _open(EmployeeLesson lesson) async {
    await context.push(
      '/funcionario/course/${widget.courseId}/lesson/${lesson.id}',
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(employeeCourseProvider(widget.courseId));
    final available = course.asData?.value;
    final pages = available == null
        ? <AsyncValue<LearningPage<EmployeeLesson>>>[]
        : [
            for (var offset = 0; offset <= _offset; offset += 50)
              ref.watch(employeeLessonsProvider(_query(offset))),
          ];
    final lessons = [for (final page in pages) ...?page.asData?.value.items];
    final total = pages.isEmpty ? null : pages.first.asData?.value.total;
    final complete =
        total != null &&
        total > 0 &&
        total == lessons.length &&
        lessons.every((lesson) => lesson.completed);
    final next = lessons
        .where((lesson) => lesson.playable && !lesson.completed)
        .firstOrNull;
    return Theme(
      data: EmployeeStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detalhes'),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: () =>
                leaveManagementPage(context, '/funcionario/modulos'),
            icon: const SvgIcon(AppIcons.arrowBack),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            _refresh();
            try {
              await ref.read(employeeCourseProvider(widget.courseId).future);
            } catch (_) {}
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: EmployeeResult(
                  result: course,
                  retry: () =>
                      ref.invalidate(employeeCourseProvider(widget.courseId)),
                  builder: (data) => data == null
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: AppCard(
                            child: Text(
                              'Conteúdo indisponível. O acesso pode ter sido pausado ou removido pela empresa ou pela plataforma.',
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                LearningCover(
                                  url: data.coverUrl,
                                  width: double.infinity,
                                  height: 180,
                                ),
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: AppColors.navy.withValues(
                                      alpha: 0.65,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 20,
                                  right: 20,
                                  bottom: 20,
                                  child: Text(
                                    data.title,
                                    style: AdminStyles.pageTitle.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Disponível para ${ref.watch(sessionProvider).value?.active?.companyName ?? 'sua empresa'}',
                                    style: AdminStyles.fieldLabel.copyWith(
                                      color: AppColors.successDarkGreen,
                                    ),
                                  ),
                                  if (data.description?.isNotEmpty == true) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      data.description!,
                                      style: AdminStyles.body,
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Conteúdos',
                                    style: AdminStyles.cardTitle,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        if (pages[i].hasError)
                          DataErrorCard(
                            message: 'Não foi possível carregar as aulas.',
                            retry: () => ref.invalidate(
                              employeeLessonsProvider(_query(i * 50)),
                            ),
                          ),
                      if (pages.any((page) => page.isLoading))
                        const DataSkeleton(),
                      if (total == 0)
                        const AppCard(
                          child: Text('Este curso ainda não possui aulas.'),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: lessons.length,
                  itemBuilder: (_, index) {
                    final lesson = lessons[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (index == 0 ||
                              lessons[index - 1].moduleId != lesson.moduleId)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                lesson.moduleTitle,
                                style: AdminStyles.fieldLabel,
                              ),
                            ),
                          AppCard(
                            padding: const EdgeInsets.all(14),
                            onTap: lesson.playable ? () => _open(lesson) : null,
                            child: Row(
                              children: [
                                SvgIcon(
                                  lesson.completed
                                      ? AppIcons.checkCircle
                                      : lesson.playable
                                      ? AppIcons.playCircle
                                      : AppIcons.lock,
                                  color: AppColors.successDarkGreen,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lesson.title,
                                        style: AdminStyles.cardTitle,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        !lesson.playable
                                            ? 'Reprodução deste formato disponível em breve'
                                            : lesson.completed
                                            ? 'Concluída'
                                            : lesson.positionSec > 0
                                            ? 'Em andamento · retomar aos ${lesson.positionSec}s'
                                            : 'Disponível',
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
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (total != null &&
                          lessons.length < total &&
                          pages.last.asData?.value.items.length == 50)
                        TextButton(
                          onPressed: () => setState(() => _offset += 50),
                          child: const Text('Carregar mais aulas'),
                        ),
                      if (next != null)
                        FilledButton(
                          onPressed: () => _open(next),
                          child: const Text('Continuar curso'),
                        ),
                      if (complete)
                        FilledButton(
                          onPressed: _issuing ? null : _issue,
                          child: Text(
                            _issuing ? 'Emitindo...' : 'Emitir certificado',
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
