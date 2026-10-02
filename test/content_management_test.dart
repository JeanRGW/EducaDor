import 'dart:async';
import 'dart:typed_data';

import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/content/catalog_screen.dart';
import 'package:educador/features/content/cover_image.dart';
import 'package:educador/features/content/publish_video_screen.dart';
import 'package:educador/shared/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

const _gestorUser = User(
  id: 'gestor',
  fullName: 'Gestora Marina',
  email: 'marina@example.test',
  initials: 'GM',
);

class _GestorSession extends SessionController {
  @override
  Future<AppSession?> build() async => const AppSession(
    user: _gestorUser,
    contexts: [],
    active: AccessContext(role: Role.gestor, companyName: 'Plataforma'),
  );
}

class _People extends PeopleRepository {
  @override
  Future<List<ProfessionalOption>> platformProfessionals({
    String search = '',
  }) async =>
      [
            const ProfessionalOption(id: 'gestor', name: 'Gestora Marina'),
            const ProfessionalOption(id: 'other', name: 'Outro Gestor'),
          ]
          .where(
            (person) =>
                person.name.toLowerCase().contains(search.toLowerCase()),
          )
          .toList();
}

class _Catalog extends ContentRepository {
  String title = 'Segurança no trabalho';
  double? completionPct = 84;
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
  String? publishedCover;
  String? publishedResponsible;
  int coverUploads = 0;

  @override
  Future<String> publishVideo({
    required String title,
    required String description,
    required String moduleTitle,
    required String videoId,
    required ContentAudience audience,
    String? coverKey,
    String? responsibleId,
  }) async {
    publishedAudience = audience;
    publishedVideo = videoId;
    publishedCover = coverKey;
    publishedResponsible = responsibleId;
    return 'content';
  }

  @override
  Future<({String key, String putUrl})> requestCoverUpload({
    required int size,
  }) async {
    coverUploads++;
    return (key: 'covers/test.webp', putUrl: 'https://example.test/put');
  }

  @override
  Future<void> uploadCoverBytes({
    required String putUrl,
    required Uint8List bytes,
  }) async {}

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
        title: title,
        kind: 'course',
        platformEnabled: platformEnabled,
        companyEnabled: companyEnabled,
        allCompanies: audience.allCompanies,
        companyIds: audience.companyIds,
        companyCount: audience.allCompanies ? 2 : audience.companyIds.length,
        lessonCount: 4,
        completionPct: completionPct,
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

class _PagedCatalog extends _Catalog {
  final List<int> offsets = [];

  @override
  Future<List<ManagedContent>> catalog({
    String search = '',
    String? kind,
    int offset = 0,
  }) async {
    offsets.add(offset);
    return [
      for (var i = offset; i < offset + 50; i++)
        ManagedContent(
          id: 'content-$i',
          title: 'Curso $i',
          kind: 'course',
          coverUrl: 'https://example.test/covers/$i.webp',
          platformEnabled: true,
          companyEnabled: true,
          allCompanies: true,
          companyIds: const [],
          companyCount: 2,
          lessonCount: 4,
          completionPct: 84,
        ),
    ];
  }
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
  for (final platform in [false, true]) {
    testWidgets(
      'catalog cards and covers stay lazy after pagination (platform: $platform)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = _PagedCatalog();
        await _showCatalog(tester, repo, platform: platform);
        final cards = find.byType(ManagedContentCard);
        final covers = find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is NetworkImage,
        );

        void expectLazyPage() {
          expect(cards.evaluate().length, inInclusiveRange(1, 9));
          expect(covers.evaluate().length, cards.evaluate().length);
        }

        expect(repo.offsets, [0]);
        expectLazyPage();
        expect(find.text('Curso 0'), findsOneWidget);
        expect(find.text('Curso 49'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Carregar mais conteúdo'),
          1000,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expectLazyPage();
        expect(find.text('Curso 0'), findsNothing);
        await tester.tap(find.text('Carregar mais conteúdo'));
        await tester.pumpAndSettle();
        expect(repo.offsets, [0, 50]);
        await tester.scrollUntilVisible(
          find.text('Curso 50'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expectLazyPage();
        expect(find.text('Curso 99'), findsNothing);
        expect(find.text('Curso 0'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Carregar mais conteúdo'),
          1000,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Curso 99'), findsOneWidget);
        expectLazyPage();
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets(
    'platform catalog matches prototype styling and keeps access actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Catalog();
      await _showCatalog(tester, repo, platform: true);

      expect(tester.getTopLeft(find.text('Conteúdo Educacional')).dx, 16);
      expect(tester.getSize(find.byType(TextField)).height, 36);
      expect(tester.getSize(find.byType(FilterChips)).height, 28);
      expect(
        tester.widget<FilterChips>(find.byType(FilterChips)).plainInactive,
        isTrue,
      );
      final titleStyle = tester.widget<Text>(find.text(repo.title)).style!;
      expect(titleStyle.fontFamily, AppFonts.outfit);
      expect(titleStyle.fontSize, 14);
      expect(titleStyle.fontWeight, FontWeight.w700);
      expect(tester.widget<ProgressBar>(find.byType(ProgressBar)).height, 4);
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.activeThumbColor, Colors.white);
      expect(toggle.activeTrackColor, AppColors.successDarkGreen);
      expect(
        tester.getCenter(find.byType(Switch)).dx,
        lessThan(tester.getTopLeft(find.text('Acesso liberado')).dx),
      );
      expect(find.text('Liberar para'), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .shape,
        isA<CircleBorder>(),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(repo.platformWrites, 1);
      expect(find.text('Pausado pela plataforma'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(repo.title)).style!.color,
        AppColors.textMuted,
      );
      expect(find.text('84%'), findsOneWidget);
      expect(find.text('Liberar para'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'platform catalog fits long titles and no-data metrics with larger text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Catalog()
        ..title =
            'Segurança no trabalho e cuidados com a saúde dos funcionários'
        ..completionPct = null
        ..audience = const ContentAudience(
          allCompanies: false,
          companyIds: ['a'],
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [contentRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const ContentCatalogScreen(platform: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sem dados'), findsOneWidget);
      expect(
        find.textContaining('1 empresa liberada', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
        overrides: [
          contentRepositoryProvider.overrideWithValue(repo),
          peopleRepositoryProvider.overrideWithValue(_People()),
          sessionProvider.overrideWith(_GestorSession.new),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Todas as empresas'), findsOneWidget);
    expect(find.text('Gestora Marina'), findsOneWidget);
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
    expect(repo.publishedResponsible, 'gestor');
    expect(repo.publishedCover, isNull);
    expect(repo.coverUploads, 0);
    expect(find.text('Trilha publicada.'), findsOneWidget);
  });

  testWidgets('responsible professional can be changed before publishing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _Catalog();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const PublishVideoScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(repo),
          peopleRepositoryProvider.overrideWithValue(_People()),
          sessionProvider.overrideWith(_GestorSession.new),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Gestora Marina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestora Marina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outro Gestor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar seleção'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Nova trilha');
    await tester.enterText(
      find.byType(TextFormField).at(3),
      'https://youtu.be/abcdefghijk',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publicar'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.publishedResponsible, 'other');
  });

  testWidgets('cover picker completion after disposal is ignored', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    final selection = Completer<String?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => selection.future,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(_GestorSession.new)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const PublishVideoScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Toque para escolher uma imagem'));
    await tester.tap(find.text('Toque para escolher uma imagem'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    selection.complete('/unused-cover.png');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('cover images fit 1200px and 200KB, invalid input is rejected', () {
    final photo = img.Image(width: 2000, height: 1000);
    for (final pixel in photo) {
      pixel
        ..r = pixel.x % 256
        ..g = pixel.y % 256
        ..b = (pixel.x + pixel.y) % 256;
    }
    final processed = processCoverImage(img.encodePng(photo))!;
    final decoded = img.decodeImage(processed)!;
    expect(decoded.width, 1200);
    expect(decoded.height, 600);
    expect(processed.length, lessThanOrEqualTo(200 * 1024));
    expect(processCoverImage(Uint8List(0)), isNull);
    expect(processCoverImage(Uint8List.fromList([1, 2, 3])), isNull);
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
