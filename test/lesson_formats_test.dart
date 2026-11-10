import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/content/animated_lesson.dart';
import 'package:educador/features/content/lesson_editor.dart';
import 'package:educador/features/employee/content_player.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

class _Content extends ContentRepository {
  Uint8List? uploaded;
  String? uploadedMime;
  @override
  Future<List<String>> lessonFileUrls(
    String lessonId,
    List<String> keys,
  ) async => keys.map((_) => 'https://example.test/image.png').toList();
  @override
  Future<String> uploadLessonFile(Uint8List bytes, String contentType) async {
    uploaded = bytes;
    uploadedMime = contentType;
    return contentType == 'image/gif' ? 'lessons/test.gif' : 'lessons/test.png';
  }

  ContentLesson? current;
  @override
  Future<ContentLesson> lesson(String id) async => current!;
  Map<String, dynamic>? saved;
  String? savedKind;
  @override
  Future<void> saveContentLesson({
    required String moduleId,
    required String title,
    required String kind,
    required Map<String, dynamic> data,
    String? id,
  }) async {
    saved = data;
    savedKind = kind;
  }
}

class _LearningContent extends EmployeeLearningRepository {
  final _Content content;
  _LearningContent(this.content);
  @override
  Future<ContentLesson> lessonContent(String lessonId) async =>
      content.current!;
}

class _Picker extends FilePicker {
  final Uint8List bytes;
  final String name;
  _Picker(this.bytes, {this.name = 'animation.gif'});
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
  }) async => FilePickerResult([
    PlatformFile(
      name: name,
      size: bytes.length,
      readStream: Stream.value(bytes),
    ),
  ]);
}

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async => const AppSession(
    user: User(
      id: 'u',
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

class _Progress extends ProgressRepository {
  final writes = <({String companyId, String lessonId, bool completed})>[];
  @override
  Future<void> save(
    String companyId,
    String lessonId, {
    required int positionSec,
    required bool completed,
    String? contentGender,
  }) async {
    writes.add((
      companyId: companyId,
      lessonId: lessonId,
      completed: completed,
    ));
  }
}

void main() {
  testWidgets('single image uploads use the existing private media flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bytes = Uint8List.fromList([137, 80, 78, 71]);
    FilePicker.platform = _Picker(bytes, name: 'image.png');
    final repo = _Content();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [contentRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: LessonEditor(
            module: ContentModule(id: 'm', title: 'Módulo'),
            lesson: ContentLesson(
              id: 'l',
              title: 'Imagem',
              kind: 'animation',
              moduleId: 'm',
              data: {'body': 'Legenda'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar imagem (PNG, JPG ou WebP)'));
    await tester.pumpAndSettle();
    expect(repo.uploadedMime, 'image/png');
    expect(repo.uploaded, bytes);
    expect(find.text('Duração de cada quadro (ms)'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Salvar aula'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Salvar aula'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Salvar aula'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.saved!['file_key'], 'lessons/test.png');
    expect(repo.saved!['body'], 'Legenda');
    expect(repo.saved!['image_keys'], isEmpty);
  });
  testWidgets(
    'single image viewer offers zoom, supporting text and completion, not animation controls',
    (tester) async {
      final content = _Content()
        ..current = const ContentLesson(
          id: 'image',
          title: 'Imagem',
          kind: 'animation',
          moduleId: 'm',
          data: {'file_key': 'lessons/test.png', 'body': 'Texto da imagem'},
        );
      final progress = _Progress();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(_Session.new),
          contentRepositoryProvider.overrideWithValue(content),
          employeeLearningRepositoryProvider.overrideWithValue(
            _LearningContent(content),
          ),
          progressRepositoryProvider.overrideWithValue(progress),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ContentPlayer(
              courseId: 'course',
              lesson: EmployeeLesson(
                id: 'image',
                title: 'Imagem',
                moduleId: 'm',
                moduleTitle: 'Módulo',
                kind: 'animation',
                status: 'not_started',
                positionSec: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(AnimatedLesson), findsNothing);
      expect(find.text('Texto da imagem'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Concluir aula'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Concluir aula'));
      await tester.pumpAndSettle();
      expect(progress.writes.single.completed, isTrue);
    },
  );
  testWidgets(
    'GIF uploads retain the original bytes rather than cover processing',
    (tester) async {
      final bytes = Uint8List.fromList([71, 73, 70, 56, 57, 97]);
      FilePicker.platform = _Picker(bytes);
      final repo = _Content();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [contentRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(
            home: LessonEditor(
              module: ContentModule(id: 'm', title: 'Módulo'),
              lesson: ContentLesson(
                id: 'l',
                title: 'GIF',
                kind: 'animation',
                moduleId: 'm',
                data: {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Enviar GIF'));
      await tester.tap(find.text('Enviar GIF'));
      await tester.pumpAndSettle();
      expect(repo.uploaded, bytes);
      expect(repo.uploadedMime, 'image/gif');
      expect(find.textContaining('test.gif'), findsOneWidget);
    },
  );
  testWidgets(
    'quiz only completes after correct answers in the active company',
    (tester) async {
      final content = _Content()
        ..current = const ContentLesson(
          id: 'quiz',
          title: 'Quiz',
          kind: 'quiz',
          moduleId: 'm',
          data: {
            'quiz_json': [
              {
                'question': 'Como cuidar da postura?',
                'options': ['Com pausas', 'Sem pausas'],
                'answer': 0,
              },
            ],
          },
        );
      final progress = _Progress();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(_Session.new),
          contentRepositoryProvider.overrideWithValue(content),
          employeeLearningRepositoryProvider.overrideWithValue(
            _LearningContent(content),
          ),
          progressRepositoryProvider.overrideWithValue(progress),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ContentPlayer(
              courseId: 'course',
              lesson: const EmployeeLesson(
                id: 'quiz',
                title: 'Quiz',
                moduleId: 'm',
                moduleTitle: 'Módulo',
                kind: 'quiz',
                status: 'not_started',
                positionSec: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sem pausas'));
      await tester.tap(find.text('Concluir aula'));
      await tester.pumpAndSettle();
      expect(progress.writes, isEmpty);
      expect(find.textContaining('Revise suas respostas'), findsOneWidget);
      await tester.tap(find.text('Com pausas'));
      await tester.tap(find.text('Concluir aula'));
      await tester.pumpAndSettle();
      expect(progress.writes, [
        (companyId: 'company', lessonId: 'quiz', completed: true),
      ]);
      expect(find.text('Concluída'), findsOneWidget);
    },
  );
  test('every lesson format is available to employees', () {
    for (final kind in lessonTypeLabels.keys) {
      expect(
        EmployeeLesson(
          id: 'l',
          title: 'Aula',
          moduleId: 'm',
          moduleTitle: 'Módulo',
          kind: kind,
          status: 'not_started',
          videoId: kind == 'video' ? 'abcdefghijk' : null,
          positionSec: 0,
        ).playable,
        isTrue,
      );
    }
  });
  testWidgets('sequence advances, pauses and steps manually', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnimatedLesson(
            urls: ['https://example.test/1.png', 'https://example.test/2.png'],
            frameMs: 500,
          ),
        ),
      ),
    );
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('Pausar'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('Próximo'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('reduced motion starts GIF and sequence paused', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final gif in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: AnimatedLesson(
                key: ValueKey(gif),
                gif: gif,
                urls: const [
                  'https://example.test/1.gif',
                  'https://example.test/2.png',
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Reproduzir'), findsOneWidget);
      expect(
        tester.widget<TickerMode>(find.byType(TickerMode).last).enabled,
        isFalse,
      );
      await tester.pump(const Duration(seconds: 2));
      if (!gif) expect(find.text('1 / 2'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final type in lessonTypeLabels.keys) {
    testWidgets('$type editor preserves typed content on save', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Content();
      final data = <String, dynamic>{
        'body': 'Texto da aula',
        'video_id': 'abcdefghijk',
        'file_key': switch (type) {
          'audio' => 'lessons/a.mp3',
          'pdf' => 'lessons/a.pdf',
          'animation' => 'lessons/a.gif',
          _ => null,
        },
        'quiz_json': [
          {
            'question': 'Pergunta?',
            'options': ['Sim', 'Não'],
            'answer': 0,
          },
        ],
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [contentRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: LessonEditor(
              module: const ContentModule(id: 'm', title: 'Módulo'),
              lesson: ContentLesson(
                id: 'l',
                title: 'Aula',
                kind: type,
                moduleId: 'm',
                data: data,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Salvar aula'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Salvar aula'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Salvar aula'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.savedKind, type);
      expect(repo.saved!['body'], 'Texto da aula');
      if (type == 'quiz') expect(repo.saved!['questions'], data['quiz_json']);
      if (type == 'animation') expect(repo.saved!['file_key'], 'lessons/a.gif');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('frame ordering is saved independently from module title', (
    tester,
  ) async {
    final repo = _Content();
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [contentRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: LessonEditor(
            module: const ContentModule(id: 'm', title: 'Módulo'),
            lesson: const ContentLesson(
              id: 'l',
              title: 'Sequência',
              kind: 'animation',
              moduleId: 'm',
              data: {
                'image_keys': ['lessons/1.png', 'lessons/2.png'],
                'frame_ms': 500,
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descer').first);
    await tester.ensureVisible(find.text('Salvar aula'));
    await tester.tap(find.text('Salvar aula'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Salvar aula'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.saved!['image_keys'], ['lessons/2.png', 'lessons/1.png']);
    expect(repo.saved!['frame_ms'], 500);
  });
}
