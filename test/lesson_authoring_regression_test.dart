import 'dart:async';
import 'dart:typed_data';

import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/content/lesson_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository extends ContentRepository {
  Map<String, dynamic>? saved;
  String? id;
  final upload = Completer<String>();
  int uploads = 0;

  @override
  Future<String> uploadLessonFile(Uint8List bytes, String contentType) {
    uploads++;
    return upload.future;
  }

  @override
  Future<void> saveContentLesson({
    required String moduleId,
    required String title,
    required String kind,
    required Map<String, dynamic> data,
    String? id,
  }) async {
    saved = data;
    this.id = id;
  }
}

class _Picker extends FilePicker {
  final result = Completer<FilePickerResult?>();
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) => result.future;
}

Future<void> _show(
  WidgetTester tester,
  _Repository repo,
  ContentLesson lesson,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [contentRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: LessonEditor(
          module: const ContentModule(id: 'm', title: 'Módulo'),
          lesson: lesson,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar aula'));
  await tester.tap(find.widgetWithText(FilledButton, 'Salvar aula'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Salvar aula'),
    ),
  );
  await tester.pumpAndSettle();
}

const _animation = ContentLesson(
  id: 'l',
  moduleId: 'm',
  title: 'Aula',
  kind: 'animation',
  data: {
    'points': 21,
    'content_gender': 'male',
    'file_key': 'lessons/main.gif',
    'alternate_content': {'file_key': 'lessons/alt.gif'},
  },
);

void main() {
  testWidgets('cancelled picker preserves both versions and unlocks controls', (
    tester,
  ) async {
    final picker = _Picker();
    FilePicker.platform = picker;
    final repo = _Repository();
    await _show(tester, repo, _animation);
    await tester.tap(find.text('Enviar GIF').last);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Salvando...'),
          )
          .onPressed,
      isNull,
    );
    picker.result.complete(null);
    await tester.pumpAndSettle();
    await _save(tester);
    expect(repo.uploads, 0);
    expect(repo.saved!['file_key'], 'lessons/main.gif');
    expect(repo.saved!['alternate_content']['file_key'], 'lessons/alt.gif');
  });

  testWidgets(
    'pending alternate upload disables mutations and updates its original draft',
    (tester) async {
      final picker = _Picker();
      FilePicker.platform = picker;
      final repo = _Repository();
      await _show(tester, repo, _animation);
      await tester.tap(find.text('Enviar GIF').last);
      picker.result.complete(
        FilePickerResult([
          PlatformFile(
            name: 'new.gif',
            size: 2,
            readStream: Stream.value(Uint8List.fromList([1, 2])),
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(repo.uploads, 1);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Remover versão alternativa'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Enviar GIF').first,
            )
            .onPressed,
        isNull,
      );
      repo.upload.complete('lessons/new.gif');
      await tester.pumpAndSettle();
      await _save(tester);
      expect(repo.saved!['file_key'], 'lessons/main.gif');
      expect(repo.saved!['alternate_content']['file_key'], 'lessons/new.gif');
      expect(repo.id, 'l');
    },
  );

  testWidgets(
    'removing alternative explicitly clears it while preserving primary',
    (tester) async {
      final repo = _Repository();
      await _show(tester, repo, _animation);
      await tester.tap(find.text('Remover versão alternativa'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remover'),
        ),
      );
      await tester.pumpAndSettle();
      await _save(tester);
      expect(repo.saved!.containsKey('alternate_content'), isTrue);
      expect(repo.saved!['alternate_content'], isNull);
      expect(repo.saved!['content_gender'], 'male');
      expect(repo.saved!['file_key'], 'lessons/main.gif');
      expect(repo.saved!['points'], 21);
      expect(repo.id, 'l');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing split quiz round trips separate questions and shared identity',
    (tester) async {
      final repo = _Repository();
      const primary = [
        {
          'question': 'Principal?',
          'options': ['Sim', 'Não'],
          'answer': 1,
        },
      ];
      const alternate = [
        {
          'question': 'Alternativa?',
          'options': ['A', 'B'],
          'answer': 0,
        },
      ];
      await _show(
        tester,
        repo,
        const ContentLesson(
          id: 'quiz',
          moduleId: 'm',
          title: 'Quiz',
          kind: 'quiz',
          data: {
            'points': 17,
            'content_gender': 'female',
            'quiz_json': primary,
            'alternate_content': {'questions': alternate},
          },
        ),
      );
      await _save(tester);
      expect(repo.id, 'quiz');
      expect(repo.saved!['points'], 17);
      expect(repo.saved!['content_gender'], 'female');
      expect(repo.saved!['questions'], primary);
      expect(repo.saved!['alternate_content']['questions'], alternate);
      expect(
        repo.saved!['alternate_content'].containsKey('quiz_json'),
        isFalse,
      );
      expect(repo.saved!['alternate_content'].containsKey('points'), isFalse);
    },
  );

  testWidgets('animation frame order and durations are independent', (
    tester,
  ) async {
    final repo = _Repository();
    await _show(
      tester,
      repo,
      const ContentLesson(
        id: 'frames',
        moduleId: 'm',
        title: 'Quadros',
        kind: 'animation',
        data: {
          'content_gender': 'male',
          'image_keys': ['lessons/a.png', 'lessons/b.png'],
          'frame_ms': 500,
          'alternate_content': {
            'image_keys': ['lessons/c.png', 'lessons/d.png'],
            'frame_ms': 900,
          },
        },
      ),
    );
    await tester.tap(find.text('Descer').first);
    await tester.pump();
    await _save(tester);
    expect(repo.saved!['image_keys'], ['lessons/b.png', 'lessons/a.png']);
    expect(repo.saved!['frame_ms'], 500);
    expect(repo.saved!['alternate_content']['image_keys'], [
      'lessons/c.png',
      'lessons/d.png',
    ]);
    expect(repo.saved!['alternate_content']['frame_ms'], 900);
  });
}
