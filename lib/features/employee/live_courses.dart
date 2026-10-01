import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';

class LearningCatalogScreen extends ConsumerWidget {
  final String title;
  const LearningCatalogScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyId = ref.watch(sessionProvider).value?.active?.companyId;
    return _LearningCatalog(key: ValueKey(companyId), title: title);
  }
}

class _LearningCatalog extends ConsumerStatefulWidget {
  final String title;
  const _LearningCatalog({super.key, required this.title});
  @override
  ConsumerState<_LearningCatalog> createState() => _LearningCatalogState();
}

class _LearningCatalogState extends ConsumerState<_LearningCatalog> {
  List<LearningCourse>? _courses;
  bool _error = false;
  bool _loading = false;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final courses = await ref
          .read(courseRepositoryProvider)
          .available(offset: append ? _courses!.length : 0);
      if (!mounted) return;
      setState(() {
        _courses = [if (append) ..._courses!, ...courses];
        _more = courses.length == 50;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(automaticallyImplyLeading: false, title: Text(widget.title)),
    body: RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error)
            TextButton(
              onPressed: () => _load(),
              child: const Text('Não foi possível carregar. Tentar novamente'),
            ),
          if (_courses == null && !_error) const _CourseSkeleton(),
          if (_courses?.isEmpty == true && !_error)
            const AppCard(
              child: Text(
                'Nenhum curso disponível. A empresa ou a plataforma pode ter pausado o acesso.',
              ),
            ),
          for (final course in _courses ?? <LearningCourse>[]) ...[
            AppCard(
              onTap: () async {
                await context.push('/funcionario/course/${course.id}');
                if (mounted) _load();
              },
              child: Row(
                children: [
                  const SvgIcon(
                    AppIcons.book,
                    color: AppColors.successDarkGreen,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (course.description?.isNotEmpty == true)
                          Text(
                            course.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SvgIcon(
                    AppIcons.chevronRight,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_more)
            TextButton(
              onPressed: _loading ? null : () => _load(append: true),
              child: Text(_loading ? 'Carregando...' : 'Carregar mais cursos'),
            ),
        ],
      ),
    ),
  );
}

class LearningCourseScreen extends ConsumerWidget {
  final String courseId;
  const LearningCourseScreen({super.key, required this.courseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyId = ref.watch(sessionProvider).value?.active?.companyId;
    return _CourseOutline(
      key: ValueKey((companyId, courseId)),
      courseId: courseId,
    );
  }
}

class _CourseOutline extends ConsumerStatefulWidget {
  final String courseId;
  const _CourseOutline({super.key, required this.courseId});
  @override
  ConsumerState<_CourseOutline> createState() => _CourseOutlineState();
}

class _CourseOutlineState extends ConsumerState<_CourseOutline> {
  LearningCourse? _course;
  List<LearningLesson> _lessons = [];
  bool _loading = false;
  bool _loaded = false;
  bool _more = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final repo = ref.read(courseRepositoryProvider);
      final course = await repo.byId(widget.courseId);
      final lessons = course == null
          ? <LearningLesson>[]
          : await repo.lessons(course.id, offset: append ? _lessons.length : 0);
      if (!mounted) return;
      setState(() {
        _course = course;
        _lessons = [if (append && course != null) ..._lessons, ...lessons];
        _loaded = true;
        _more = lessons.length == 50;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalhes da trilha')),
    body: RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error)
            TextButton(
              onPressed: () => _load(),
              child: const Text('Não foi possível carregar. Tentar novamente'),
            ),
          if (!_loaded && !_error) const _CourseSkeleton(),
          if (_loaded && _course == null)
            const AppCard(
              child: Text(
                'Conteúdo indisponível. O acesso pode ter sido pausado ou removido pela empresa ou pela plataforma.',
              ),
            ),
          if (_course != null) ...[
            Text(_course!.title, style: Theme.of(context).textTheme.titleLarge),
            if (_course!.description?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(_course!.description!),
            ],
            const SectionHeader('Conteúdos'),
            for (final lesson in _lessons) ...[
              AppCard(
                child: Row(
                  children: [
                    SvgIcon(
                      switch (lesson.kind) {
                        CourseKind.video => AppIcons.play,
                        CourseKind.audio => AppIcons.headphones,
                        CourseKind.pdf => AppIcons.pdf,
                        CourseKind.quiz => AppIcons.quiz,
                        _ => AppIcons.book,
                      },
                      color: AppColors.successDarkGreen,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            lesson.moduleTitle,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Text('A reprodução dos conteúdos ainda não está disponível.'),
            if (_more)
              TextButton(
                onPressed: _loading ? null : () => _load(append: true),
                child: Text(_loading ? 'Carregando...' : 'Carregar mais aulas'),
              ),
          ],
        ],
      ),
    ),
  );
}

class _CourseSkeleton extends StatelessWidget {
  const _CourseSkeleton();
  @override
  Widget build(BuildContext context) => const AppCard(
    child: SizedBox(
      height: 64,
      width: double.infinity,
      child: ColoredBox(color: AppColors.chipBg),
    ),
  );
}
