import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/content/course_structure.dart';
import 'package:educador/features/content/delete_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Content extends ContentRepository {
  final modulesOrder = ['first', 'second'];
  final lessonsOrder = ['first', 'second'];
  final moduleOffsets = <int>[];
  final moves = <({String kind, String id, int direction})>[];
  bool fail = false;
  final deleted = <String>[];
  @override
  Future<void> deleteContent(String kind, String id) async {
    if (fail) throw StateError('Offline');
    deleted.add(id);
    (kind == 'module' ? modulesOrder : lessonsOrder).remove(id);
  }

  @override
  Future<List<ContentModule>> modules(String courseId, {int offset = 0}) async {
    moduleOffsets.add(offset);
    return modulesOrder
        .skip(offset)
        .take(50)
        .map((id) => ContentModule(id: id, title: 'Módulo $id'))
        .toList();
  }

  @override
  Future<List<ContentLesson>> moduleLessons(
    String moduleId, {
    int offset = 0,
  }) async => lessonsOrder
      .map(
        (id) => ContentLesson(
          id: id,
          title: 'Aula $id',
          kind: 'reading',
          moduleId: moduleId,
          data: const {'body': 'Texto'},
        ),
      )
      .toList();
  @override
  Future<void> moveItem(String kind, String id, int direction) async {
    moves.add((kind: kind, id: id, direction: direction));
    if (fail) throw StateError('Offline');
    final order = kind == 'module' ? modulesOrder : lessonsOrder;
    final index = order.indexOf(id);
    order.removeAt(index);
    order.insert(index + direction, id);
  }
}

void main() {
  testWidgets(
    'destructive confirmation remains readable on narrow screens with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => confirmContentDeletion(
                  context,
                  'course',
                  'Curso com um título muito longo',
                ),
                child: const Text('Excluir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('module reorder retains loaded pages', (tester) async {
    final repo = _Content();
    repo.modulesOrder
      ..clear()
      ..addAll(List.generate(51, (i) => 'item$i'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [contentRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: CourseStructure(courseId: 'course')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Carregar mais módulos'),
      1000,
      maxScrolls: 50,
    );
    await tester.tap(find.text('Carregar mais módulos'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Módulo item50'), 200);
    final up = find.byWidgetPredicate(
      (w) => w is IconButton && w.tooltip == 'Mover módulo para cima',
    );
    await tester.ensureVisible(up.last);
    await tester.tap(up.last);
    await tester.pumpAndSettle();
    expect(repo.modulesOrder[49], 'item50');
    expect(repo.moduleOffsets.sublist(repo.moduleOffsets.length - 2), [0, 50]);
    expect(tester.takeException(), isNull);
  });
  for (final kind in ['module', 'lesson']) {
    testWidgets('$kind deletion requires confirmation and refreshes the list', (
      tester,
    ) async {
      final repo = _Content();
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [contentRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: kind == 'module'
                ? const Scaffold(body: CourseStructure(courseId: 'course'))
                : const ModuleManagementScreen(
                    module: ContentModule(id: 'module', title: 'Módulo'),
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = kind == 'module' ? 'módulo' : 'aula';
      await tester.tap(find.text('Excluir $label').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      repo.fail = true;
      await tester.tap(find.text('Excluir $label').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Excluir $label'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      expect(find.textContaining('Não foi possível excluir'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      repo.fail = false;
      await tester.tap(find.text('Excluir $label').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Excluir $label'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.deleted, ['first']);
      expect(
        find.text(kind == 'module' ? 'Módulo first' : 'Aula first'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('$kind controls persist order and disable boundary moves', (
      tester,
    ) async {
      final repo = _Content();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [contentRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: kind == 'module'
                ? const Scaffold(body: CourseStructure(courseId: 'course'))
                : const ModuleManagementScreen(
                    module: ContentModule(id: 'module', title: 'Módulo'),
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = kind == 'module' ? 'módulo' : 'aula';
      final title = kind == 'module' ? 'Módulo' : 'Aula';
      final up = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Mover $label para cima',
      );
      expect(tester.widget<IconButton>(up.first).onPressed, isNull);
      await tester.tap(up.last);
      await tester.pumpAndSettle();
      expect(repo.moves.single, (kind: kind, id: 'second', direction: -1));
      expect(
        tester.getTopLeft(find.text('$title second')).dy,
        lessThan(tester.getTopLeft(find.text('$title first')).dy),
      );
      expect(tester.widget<IconButton>(up.first).onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(
              find
                  .byWidgetPredicate(
                    (w) =>
                        w is IconButton &&
                        w.tooltip == 'Mover $label para baixo',
                  )
                  .last,
            )
            .onPressed,
        isNull,
      );
      repo.fail = true;
      await tester.tap(up.last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Não foi possível alterar a ordem'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('$title second')).dy,
        lessThan(tester.getTopLeft(find.text('$title first')).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'lesson creation uses a floating plus and compact edit typography',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [contentRepositoryProvider.overrideWithValue(_Content())],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ModuleManagementScreen(
              module: ContentModule(id: 'm', title: 'Módulo'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Adicionar aula'), findsNothing);
      expect(find.byTooltip('Adicionar aula'), findsOneWidget);
      final theme = TextButtonTheme.of(
        tester.element(find.text('Editar aula').first),
      );
      expect(theme.style!.textStyle!.resolve({})!.fontSize, 12);
      await tester.tap(find.byTooltip('Adicionar aula'));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar aula'), findsOneWidget);
    },
  );
}
