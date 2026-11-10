import 'dart:async';

import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/employee_providers.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/playback_progress.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/employee/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends SessionController {
  AppSession session(Gender? gender) => AppSession(
    user: User(
      id: 'u',
      fullName: 'Ana',
      email: 'a@b.test',
      initials: 'A',
      gender: gender,
    ),
    contexts: const [],
    active: const AccessContext(
      role: Role.funcionario,
      companyId: 'c',
      companyName: 'C',
    ),
  );
  @override
  Future<AppSession?> build() async => session(Gender.male);
  void change(Gender? gender) => state = AsyncData(session(gender));
}

class _Learning extends EmployeeLearningRepository {
  final pages = <Completer<LearningPage<EmployeeLesson>>>[];
  final contents = <Completer<ContentLesson>>[];
  @override
  Future<LearningPage<EmployeeLesson>> lessons(
    String companyId,
    String courseId, {
    int offset = 0,
  }) {
    final result = Completer<LearningPage<EmployeeLesson>>();
    pages.add(result);
    return result.future;
  }

  @override
  Future<ContentLesson> lessonContent(String lessonId) {
    final result = Completer<ContentLesson>();
    contents.add(result);
    return result.future;
  }
}

class _Files extends ContentRepository {
  int downloads = 0;
  @override
  Future<List<String>> lessonFileUrls(
    String lessonId,
    List<String> keys,
  ) async {
    downloads++;
    return [];
  }
}

class _Progress extends ProgressRepository {
  final writes = <({String? gender, bool completed, int position})>[];
  final pending = <Completer<void>>[];
  @override
  Future<void> save(
    String companyId,
    String lessonId, {
    required int positionSec,
    required bool completed,
    String? contentGender,
  }) {
    writes.add((
      gender: contentGender,
      completed: completed,
      position: positionSec,
    ));
    final result = Completer<void>();
    pending.add(result);
    return result.future;
  }
}

EmployeeLesson _lesson(String gender) => EmployeeLesson(
  id: 'l',
  title: 'Aula',
  moduleId: 'm',
  moduleTitle: 'Módulo',
  kind: 'reading',
  status: 'completed',
  positionSec: 0,
  contentGender: gender,
);
LearningPage<EmployeeLesson> _page(String gender) =>
    LearningPage(items: [_lesson(gender)], total: 1);
ContentLesson _content(String gender, String body) => ContentLesson(
  id: 'l',
  title: 'Aula',
  moduleId: 'm',
  kind: 'reading',
  data: {'content_gender': gender, 'body': body, 'file_key': 'lessons/old.png'},
);

void main() {
  test(
    'queued checkpoints cannot write after scope changes and retain actual tag and completion',
    () async {
      final repo = _Progress();
      var current = true;
      final progress = PlaybackProgress(
        repository: repo,
        companyId: 'c',
        lessonId: 'l',
        contentGender: 'neutral',
        isCurrent: () => current,
        positionSec: 0,
        completed: true,
      );
      progress.update(
        const Duration(seconds: 20),
        const Duration(seconds: 100),
      );
      final first = progress.save(force: true);
      final second = progress.save(force: true);
      expect(repo.writes.single, (
        gender: 'neutral',
        completed: true,
        position: 20,
      ));
      current = false;
      final rejected = expectLater(second, throwsStateError);
      repo.pending.single.complete();
      await first;
      await rejected;
      expect(repo.writes.length, 1);
    },
  );

  testWidgets(
    'gender refresh rejects old in-flight content before requesting files',
    (tester) async {
      final learning = _Learning();
      final files = _Files();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(_Session.new),
          employeeLearningRepositoryProvider.overrideWithValue(learning),
          contentRepositoryProvider.overrideWithValue(files),
          progressRepositoryProvider.overrideWithValue(_Progress()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      final scope = container.read(employeeScopeProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: EmployeePlayerScreen(courseId: 'course', lessonId: 'l'),
          ),
        ),
      );
      learning.pages.single.complete(_page('male'));
      await tester.pump();
      await tester.pump();
      expect(learning.contents.length, 1);
      (container.read(sessionProvider.notifier) as _Session).change(
        Gender.female,
      );
      expect(container.read(employeeScopeProvider), scope);
      await tester.pump();
      expect(learning.pages.length, 2);
      learning.contents.first.complete(_content('male', 'Conteúdo antigo'));
      learning.pages.last.complete(_page('female'));
      await tester.pump();
      await tester.pump();
      expect(files.downloads, 0);
      expect(find.text('Conteúdo antigo'), findsNothing);
      expect(learning.contents.length, 2);
      learning.contents.last.complete(_content('female', 'Conteúdo novo'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Conteúdo novo'), findsOneWidget);
      expect(find.text('Concluída'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('obsolete paginated loader does not request later pages', (
    tester,
  ) async {
    final learning = _Learning();
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        employeeLearningRepositoryProvider.overrideWithValue(learning),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: EmployeePlayerScreen(courseId: 'course', lessonId: 'l'),
        ),
      ),
    );
    (container.read(sessionProvider.notifier) as _Session).change(
      Gender.female,
    );
    await tester.pump();
    learning.pages.first.complete(
      const LearningPage(
        items: [
          EmployeeLesson(
            id: 'other',
            title: 'Outra',
            moduleId: 'm',
            moduleTitle: 'Módulo',
            kind: 'reading',
            status: 'not_started',
            positionSec: 0,
          ),
        ],
        total: 100,
      ),
    );
    await tester.pump();
    expect(learning.pages.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
