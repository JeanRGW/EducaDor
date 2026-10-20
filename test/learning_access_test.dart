import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/employee/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async => const AppSession(
    user: User(
      id: 'employee',
      fullName: 'Ana',
      email: 'ana@example.test',
      initials: 'A',
    ),
    contexts: [],
    active: AccessContext(
      role: Role.funcionario,
      companyId: 'company',
      companyName: 'Empresa',
    ),
  );
}

class _Courses extends EmployeeLearningRepository {
  bool availableNow = true;
  int lessonsRead = 0;
  @override
  Future<LearningCourse?> course(String id) async => availableNow
      ? const LearningCourse(id: 'course', title: 'Segurança no trabalho')
      : null;
  @override
  Future<LearningPage<LearningItem>> catalog(
    String companyId, {
    String search = '',
    String? kind,
    String? state,
    int offset = 0,
  }) async => LearningPage(
    total: availableNow ? 1 : 0,
    items: availableNow
        ? const [
            LearningItem(
              id: 'course',
              title: 'Segurança no trabalho',
              state: 'not_started',
              lessonCount: 1,
              completedCount: 0,
            ),
          ]
        : [],
  );
  @override
  Future<LearningPage<EmployeeLesson>> lessons(
    String companyId,
    String courseId, {
    int offset = 0,
  }) async {
    lessonsRead++;
    return const LearningPage(total: 0, items: []);
  }
}

Future<void> _show(WidgetTester tester, Widget screen, _Courses repo) async {
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(_Session.new),
      employeeLearningRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('blocked direct course links do not request lessons', (
    tester,
  ) async {
    final repo = _Courses()..availableNow = false;
    await _show(tester, const CourseDetailScreen(courseId: 'course'), repo);
    expect(find.textContaining('Conteúdo indisponível.'), findsOneWidget);
    expect(repo.lessonsRead, 0);
  });
  testWidgets('employee catalog reflects access changes on refresh', (
    tester,
  ) async {
    final repo = _Courses();
    await _show(tester, const ModulesScreen(), repo);
    expect(find.text('Segurança no trabalho'), findsOneWidget);
    repo.availableNow = false;
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Segurança no trabalho'), findsNothing);
    expect(find.textContaining('Nenhum curso disponível'), findsOneWidget);
  });
}
