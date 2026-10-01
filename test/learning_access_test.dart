import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/employee/live_courses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Courses extends CourseRepository {
  bool availableNow = true;
  int lessonsRead = 0;
  static const course = LearningCourse(
    id: 'course',
    title: 'Segurança no trabalho',
  );

  @override
  Future<List<LearningCourse>> available({int offset = 0}) async =>
      availableNow ? [course] : [];

  @override
  Future<LearningCourse?> byId(String id) async => availableNow ? course : null;

  @override
  Future<List<LearningLesson>> lessons(
    String courseId, {
    int offset = 0,
  }) async {
    lessonsRead++;
    return const [
      LearningLesson(
        id: 'lesson',
        title: 'Introdução',
        moduleTitle: 'Módulo 1',
        kind: CourseKind.video,
      ),
    ];
  }
}

void main() {
  testWidgets('blocked direct course links do not request lessons', (
    tester,
  ) async {
    final repo = _Courses()..availableNow = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [courseRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const LearningCourseScreen(courseId: 'course'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Conteúdo indisponível.'), findsOneWidget);
    expect(repo.lessonsRead, 0);
    expect(find.text('Introdução'), findsNothing);
  });

  testWidgets('employee catalog reflects access changes on refresh', (
    tester,
  ) async {
    final repo = _Courses();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [courseRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const LearningCatalogScreen(title: 'Meus cursos'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_Courses.course.title), findsOneWidget);
    repo.availableNow = false;
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pumpAndSettle();
    expect(find.text(_Courses.course.title), findsNothing);
    expect(find.textContaining('Nenhum curso disponível.'), findsOneWidget);
  });
}
