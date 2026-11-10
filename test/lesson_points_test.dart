import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/content/lesson_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Content extends ContentRepository {
  Map<String, dynamic>? saved;
  String? lessonId;
  @override
  Future<void> saveContentLesson({
    required String moduleId,
    required String title,
    required String kind,
    required Map<String, dynamic> data,
    String? id,
  }) async {
    saved = data;
    lessonId = id;
  }
}

Future<void> _show(WidgetTester tester, _Content repo, {int? points}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [contentRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: LessonEditor(
          module: const ContentModule(id: 'module', title: 'Módulo'),
          lesson: points == null
              ? null
              : ContentLesson(
                  id: 'lesson',
                  moduleId: 'module',
                  title: 'Aula',
                  kind: 'video',
                  data: {'points': points, 'video_id': 'abcdefghijk'},
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _points => find.byType(TextFormField).at(1);

void main() {
  testWidgets('new lessons default to ten points and send points in data', (
    tester,
  ) async {
    final repo = _Content();
    await _show(tester, repo);
    expect(tester.widget<TextFormField>(_points).controller!.text, '10');
    await tester.enterText(find.byType(TextFormField).first, 'Aula');
    await tester.enterText(find.byType(TextFormField).at(2), 'abcdefghijk');
    await tester.tap(find.text('Salvar aula'));
    await tester.pumpAndSettle();
    expect(repo.saved?['points'], 10);
    expect(repo.saved?['content_gender'], isNull);
    expect(repo.saved?['alternate_content'], isNull);
    expect(repo.lessonId, isNull);
  });

  testWidgets('paired versions send independent content and shared points', (
    tester,
  ) async {
    final repo = _Content();
    await _show(tester, repo);
    await tester.enterText(find.byType(TextFormField).first, 'Aula');
    await tester.enterText(_points, '25');
    await tester.tap(find.text('Neutra / compartilhada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masculina').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar versão feminina'));
    await tester.pumpAndSettle();
    final videos = find.widgetWithText(TextFormField, 'URL ou ID do YouTube');
    await tester.enterText(videos.first, 'abcdefghijk');
    await tester.enterText(videos.last, 'lmnopqrstuv');
    await tester.ensureVisible(find.text('Salvar aula'));
    await tester.tap(find.text('Salvar aula'));
    await tester.pumpAndSettle();
    expect(repo.saved?['content_gender'], 'male');
    expect(repo.saved?['points'], 25);
    expect(repo.saved?['video_id'], 'abcdefghijk');
    expect(repo.saved?['alternate_content']['video_id'], 'lmnopqrstuv');
    expect(repo.saved?['alternate_content'].containsKey('points'), false);
    expect(repo.saved?['alternate_content'].containsKey('quiz_json'), false);
  });

  for (final value in [0, -5, 2147483647, -2147483648]) {
    testWidgets('edits send $value points without replacing lesson ID', (
      tester,
    ) async {
      final repo = _Content();
      await _show(tester, repo, points: 37);
      expect(tester.widget<TextFormField>(_points).controller!.text, '37');
      await tester.enterText(_points, '$value');
      await tester.tap(find.text('Salvar aula'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar aula').last);
      await tester.pumpAndSettle();
      expect(repo.saved?['points'], value);
      expect(repo.lessonId, 'lesson');
    });
  }

  for (final value in ['', '1.5', 'abc', '2147483648', '-2147483649']) {
    testWidgets('invalid integer "$value" prevents save', (tester) async {
      final repo = _Content();
      await _show(tester, repo, points: 10);
      await tester.enterText(_points, value);
      await tester.tap(find.text('Salvar aula'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Informe um número inteiro'), findsOneWidget);
      expect(repo.saved, isNull);
    });
  }
}
