import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/content/catalog_screen.dart';
import 'package:educador/features/content/publish_video_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Catalog extends ContentRepository {
  bool platformEnabled = true;
  bool companyEnabled = true;
  bool failWrite = false;
  ContentAudience audience = const ContentAudience();
  int companyWrites = 0;
  int platformWrites = 0;
  String? search;
  String? kind;
  ContentAudience? publishedAudience;
  String? publishedVideo;

  @override
  Future<List<ManagedContent>> catalog({
    String search = '',
    String? kind,
    int offset = 0,
  }) async {
    this.search = search;
    this.kind = kind;
    return [
      ManagedContent(
        id: 'content',
        title: 'Segurança no trabalho',
        kind: 'course',
        platformEnabled: platformEnabled,
        companyEnabled: companyEnabled,
        allCompanies: audience.allCompanies,
        companyIds: audience.companyIds,
        companyCount: audience.allCompanies ? 2 : audience.companyIds.length,
        lessonCount: 4,
        completionPct: 84,
      ),
    ];
  }

  @override
  Future<void> setCompanyEnabled(String courseId, bool enabled) async {
    companyWrites++;
    if (failWrite) throw StateError('Test failure');
    companyEnabled = enabled;
  }

  @override
  Future<void> setPlatformEnabled(String courseId, bool enabled) async {
    platformWrites++;
    platformEnabled = enabled;
  }

  @override
  Future<void> setAudience(String courseId, ContentAudience audience) async {
    this.audience = audience;
  }

  @override
  Future<String> publishVideo({
    required String title,
    required String description,
    required String moduleTitle,
    required String videoId,
    required ContentAudience audience,
  }) async {
    publishedAudience = audience;
    publishedVideo = videoId;
    return 'content';
  }
}

class _Companies extends CompanyRepository {
  @override
  Future<List<CompanyOption>> options({
    int offset = 0,
    String search = '',
  }) async => const [
    CompanyOption(id: 'a', name: 'Santa Maria', active: true),
    CompanyOption(id: 'b', name: 'Outra Empresa', active: true),
  ];
}

Future<void> _showCatalog(
  WidgetTester tester,
  _Catalog repo, {
  bool platform = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(repo),
        companyRepositoryProvider.overrideWithValue(_Companies()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: ContentCatalogScreen(platform: platform),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('company switch persists without changing platform state', (
    tester,
  ) async {
    final repo = _Catalog();
    await _showCatalog(tester, repo);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('Liberar para'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.companyWrites, 1);
    expect(repo.companyEnabled, isFalse);
    expect(repo.platformEnabled, isTrue);
    expect(find.text('Pausado pela empresa'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.companyEnabled, isTrue);
  });

  testWidgets(
    'platform pause disables the company switch without losing its preference',
    (tester) async {
      final repo = _Catalog()..platformEnabled = false;
      await _showCatalog(tester, repo);
      expect(find.text('Pausado pela plataforma'), findsOneWidget);
      final control = tester.widget<Switch>(find.byType(Switch));
      expect(control.onChanged, isNull);
      expect(control.value, isTrue);
      expect(repo.companyWrites, 0);
    },
  );

  testWidgets('failed switch does not appear saved', (tester) async {
    final repo = _Catalog()..failWrite = true;
    await _showCatalog(tester, repo);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.textContaining('Não foi possível atualizar'), findsOneWidget);
  });

  testWidgets('platform can pause and choose an explicit company audience', (
    tester,
  ) async {
    final repo = _Catalog();
    await _showCatalog(tester, repo, platform: true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.platformWrites, 1);
    expect(repo.companyEnabled, isTrue);
    await tester.tap(find.text('Liberar para'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirmar seleção'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Santa Maria'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar seleção'));
    await tester.pumpAndSettle();
    expect(repo.audience.allCompanies, isFalse);
    expect(repo.audience.companyIds, ['a']);
    expect(repo.platformEnabled, isFalse);
  });

  testWidgets('search and kind filters query the real repository', (
    tester,
  ) async {
    final repo = _Catalog();
    await _showCatalog(tester, repo);
    await tester.enterText(find.byType(TextField), 'segurança');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.search, 'segurança');
    await tester.tap(find.text('Quizzes'));
    await tester.pumpAndSettle();
    expect(repo.kind, 'quiz');
  });

  testWidgets('publishing defaults to all companies and stores a YouTube ID', (
    tester,
  ) async {
    final repo = _Catalog();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/add'),
              child: const Text('Adicionar'),
            ),
          ),
        ),
        GoRoute(path: '/add', builder: (_, _) => const PublishVideoScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [contentRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Todas as empresas'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Nova trilha');
    await tester.enterText(
      find.byType(TextFormField).at(3),
      'https://youtu.be/abcdefghijk',
    );
    await tester.ensureVisible(find.text('Publicar'));
    await tester.tap(find.text('Publicar'));
    await tester.pumpAndSettle();
    expect(repo.publishedVideo, 'abcdefghijk');
    expect(repo.publishedAudience?.allCompanies, isTrue);
    expect(find.text('Trilha publicada.'), findsOneWidget);
  });

  for (final width in [320.0, 1000.0]) {
    testWidgets('content cards fit at width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _showCatalog(tester, _Catalog(), platform: true);
      expect(tester.takeException(), isNull);
    });
  }

  test('YouTube input accepts supported links but not other providers', () {
    for (final value in [
      'abcdefghijk',
      'https://youtu.be/abcdefghijk?t=12',
      'https://www.youtube.com/watch?v=abcdefghijk',
      'https://youtube.com/shorts/abcdefghijk',
      'https://www.youtube.com/embed/abcdefghijk',
    ]) {
      expect(youtubeVideoId(value), 'abcdefghijk');
    }
    for (final value in [
      '',
      'short',
      'https://vimeo.com/abcdefghijk',
      'https://youtube.com.evil.test/watch?v=abcdefghijk',
      'file:///abcdefghijk',
    ]) {
      expect(youtubeVideoId(value), isNull);
    }
  });
}
