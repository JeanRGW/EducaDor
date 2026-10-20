import 'dart:async';
import 'package:educador/app/theme.dart';
import 'package:educador/app/app.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/repositories/certificate_document_repository.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/data/session/playback_progress.dart';
import 'package:educador/features/employee/screens.dart';
import 'package:educador/features/employee/widgets.dart';
import 'package:educador/shared/widgets/common.dart';
import 'package:educador/features/employee/player_screen.dart';
import 'package:educador/features/gestor/profile_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _user = User(
  id: 'ana',
  fullName: 'Ana Silva',
  email: 'ana@example.test',
  initials: 'AS',
);
const _a = AccessContext(
  role: Role.funcionario,
  companyId: 'a',
  companyName: 'Empresa A',
);
const _b = AccessContext(
  role: Role.funcionario,
  companyId: 'b',
  companyName: 'Empresa B',
);

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async =>
      const AppSession(user: _user, contexts: [_a, _b], active: _a);
  void switchCompany() {
    state = const AsyncData(
      AppSession(user: _user, contexts: [_a, _b], active: _b),
    );
    sessionRefresh.refresh();
  }

  @override
  Future<AppSession?> reload() async => state.value;
}

class _Learning extends EmployeeLearningRepository {
  final calls =
      <
        ({
          String company,
          String search,
          String? kind,
          String? state,
          int offset,
        })
      >[];
  int count = 2, balance = 50, summaryReads = 0, issued = 0;
  bool fail = false, blocked = false, redeemFailure = false;
  final redeemed = <String>[];
  Completer<LearningPage<LearningItem>>? delayed;
  List<EmployeeLesson> lessonRows = const [
    EmployeeLesson(
      id: 'first',
      title: 'Introdução',
      moduleId: 'm1',
      moduleTitle: 'Módulo 1',
      kind: 'video',
      videoId: 'abcdefghijk',
      status: 'completed',
      positionSec: 100,
    ),
    EmployeeLesson(
      id: 'next',
      title: 'Aula prática',
      moduleId: 'm1',
      moduleTitle: 'Módulo 1',
      kind: 'video',
      videoId: 'abcdefghijk',
      status: 'in_progress',
      positionSec: 42,
    ),
  ];
  LearningItem item(int index, {String company = 'a'}) => LearningItem(
    id: 'course-$index',
    title: 'Curso $index da empresa $company',
    state: index == 0 ? 'in_progress' : 'not_started',
    lessonCount: 2,
    completedCount: index == 0 ? 1 : 0,
  );
  @override
  Future<EmployeeSummary> summary(String companyId) async {
    summaryReads++;
    if (fail) throw StateError('offline');
    return EmployeeSummary(
      courseCount: 4,
      completedCourseCount: 1,
      certificateCount: 1,
      balance: companyId == 'a' ? balance : 0,
      department: companyId == 'a' ? 'Operações' : 'TI',
      activity: [
        for (var day = 1; day <= 7; day++)
          StudyActivity(DateTime(2026, 10, day), day < 6),
      ],
    );
  }

  @override
  Future<LearningPage<LearningItem>> catalog(
    String companyId, {
    String search = '',
    String? kind,
    String? state,
    int offset = 0,
  }) async {
    calls.add((
      company: companyId,
      search: search,
      kind: kind,
      state: state,
      offset: offset,
    ));
    if (fail) throw StateError('offline');
    if (delayed != null) return delayed!.future;
    final rows = [for (var i = 0; i < count; i++) item(i, company: companyId)]
        .where(
          (row) =>
              row.title.contains(search) &&
              (state == null || row.state == state),
        )
        .toList();
    return LearningPage(
      items: rows.skip(offset).take(50).toList(),
      total: rows.length,
    );
  }

  @override
  Future<LearningCourse?> course(String id) async => blocked
      ? null
      : LearningCourse(
          id: id,
          title: 'Segurança no trabalho',
          description: 'Aprenda com segurança.',
        );
  @override
  Future<LearningPage<EmployeeLesson>> lessons(
    String companyId,
    String courseId, {
    int offset = 0,
  }) async {
    if (blocked) throw StateError('Forbidden');
    return LearningPage(
      items: lessonRows.skip(offset).take(50).toList(),
      total: lessonRows.length,
    );
  }

  @override
  Future<LearningPage<EarnedCertificate>> certificates(
    String companyId, {
    int offset = 0,
  }) async => LearningPage(
    total: 1,
    items: offset == 0
        ? [
            EarnedCertificate(
              id: 'cert',
              code: 'AUD-123ABC',
              courseId: 'course',
              courseTitle: 'Segurança no trabalho',
              companyName: 'Empresa $companyId',
              employeeName: 'Ana Silva',
              issuedAt: DateTime(2026, 10, 1),
            ),
          ]
        : [],
  );
  @override
  Future<List<RedeemableReward>> rewards({int offset = 0}) async => offset == 0
      ? const [RedeemableReward(id: 'gift', title: 'Caneca térmica', cost: 20)]
      : [];
  @override
  Future<List<EmployeeRank>> ranking(String companyId) async => const [
    EmployeeRank(
      userId: 'ana',
      name: 'Ana Silva',
      department: 'Operações',
      points: 50,
    ),
  ];
  @override
  Future<void> redeem(String companyId, String rewardId) async {
    if (redeemFailure) throw StateError('unknown response');
    redeemed.add('$companyId:$rewardId');
    balance -= 20;
  }

  @override
  Future<void> issueCertificate(String companyId, String courseId) async {
    issued++;
  }
}

class _Docs extends CertificateDocumentRepository {
  EarnedCertificate? downloaded;
  @override
  Future<void> download(EarnedCertificate certificate) async {
    downloaded = certificate;
  }
}

class _Profile extends ProfileRepository {
  OwnProfile? saved;
  @override
  Future<OwnProfile> own() async =>
      const OwnProfile(fullName: 'Ana Silva', email: 'ana@example.test');
  @override
  Future<void> update(OwnProfile profile) async {
    saved = profile;
  }
}

class _Progress extends ProgressRepository {
  final writes =
      <({String company, String lesson, int position, bool completed})>[];
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> save(
    String companyId,
    String lessonId, {
    required int positionSec,
    required bool completed,
  }) async {
    writes.add((
      company: companyId,
      lesson: lessonId,
      position: positionSec,
      completed: completed,
    ));
    if (fail) throw StateError('offline');
    if (pending != null) await pending!.future;
  }
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  Widget screen, {
  _Learning? learning,
  _Docs? docs,
  _Profile? profile,
  double width = 418,
  double scale = 1,
  String location = '/',
}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(_Session.new),
      employeeLearningRepositoryProvider.overrideWithValue(
        learning ?? _Learning(),
      ),
      certificateDocumentRepositoryProvider.overrideWithValue(docs ?? _Docs()),
      profileRepositoryProvider.overrideWithValue(profile ?? _Profile()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.future);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/funcionario/modulos',
        builder: (_, _) => const ModulesScreen(),
      ),
      GoRoute(
        path: '/funcionario/perfil',
        builder: (_, _) => const EmployeeProfileScreen(),
      ),
      GoRoute(
        path: '/funcionario/perfil/edit',
        builder: (_, _) =>
            const ProfileEditScreen(fallbackLocation: '/funcionario/perfil'),
      ),
      GoRoute(
        path: '/funcionario/course/:id',
        builder: (_, state) =>
            CourseDetailScreen(courseId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/funcionario/course/:id/lesson/:lessonId',
        builder: (_, state) => Scaffold(
          body: Text('Reproduzindo ${state.pathParameters['lessonId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _visible(
  WidgetTester tester,
  Finder finder, {
  double delta = 180,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 130,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Rewards uses compact tiles, horizontal balance and current-user highlight',
    (tester) async {
      await _show(tester, const RewardsScreen());
      expect(
        (tester.getCenter(find.text('SALDO DISPONÍVEL')).dy -
                tester.getCenter(find.text('50')).dy)
            .abs(),
        lessThan(60),
      );
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .mainAxisExtent,
        198,
      );
      await _visible(tester, find.textContaining('Ana Silva (Operações)'));
      expect(
        tester.widget<AppCard>(find.byKey(const ValueKey('rank-ana'))).color,
        AppColors.successBgSoft,
      );
      expect(find.text('nível 3'), findsNothing);
    },
  );
  testWidgets('catalog keeps title and segmented tabs on the same header row', (
    tester,
  ) async {
    await _show(tester, const ModulesScreen());
    final title = find.text('MÓDULOS');
    final learning = find.text('Meu aprendizado');
    final discover = find.text('Descobrir');
    expect(find.text('Módulos e cursos'), findsNothing);
    expect(
      (tester.getCenter(title).dy - tester.getCenter(learning).dy).abs(),
      lessThan(3),
    );
    expect(
      (tester.getCenter(learning).dy - tester.getCenter(discover).dy).abs(),
      lessThan(3),
    );
    expect(
      tester.getRect(title).right,
      lessThan(tester.getRect(learning).left),
    );
    expect(
      tester.getRect(find.byType(TextField)).top,
      greaterThan(tester.getRect(title).bottom),
    );
  });
  testWidgets(
    'progress removes the approximate weekly activity section entirely',
    (tester) async {
      await _show(tester, const EmployeeProgressScreen());
      expect(find.text('Atividade nos últimos 7 dias'), findsNothing);
      expect(find.textContaining('última atualização'), findsNothing);
      expect(find.text('Cursos em andamento'), findsOneWidget);
    },
  );
  testWidgets(
    'profile uses evenly spaced stats and separate setting status labels',
    (tester) async {
      await _show(tester, const EmployeeProfileScreen());
      final first = tester.getCenter(find.text('Concluídos')).dx;
      final second = tester.getCenter(find.text('Certificados')).dx;
      final third = tester.getCenter(find.text('Pontos')).dx;
      expect(second - first, closeTo(third - second, 1));
      expect(find.text('Notificações'), findsOneWidget);
      expect(find.text('Português (Brasil)'), findsOneWidget);
      expect(find.text('Em breve'), findsNWidgets(3));
      expect(find.byType(Switch), findsNothing);
    },
  );
  setUpAll(() async {
    for (final font in {
      AppFonts.inter: 'assets/fonts/Inter-Variable.ttf',
      AppFonts.outfit: 'assets/fonts/Outfit-Variable.ttf',
    }.entries) {
      final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });
  testWidgets(
    'Home restores prototype sections with live scoped data and no fake streak',
    (tester) async {
      await _show(tester, const EmployeeHomeScreen());
      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(find.text('Empresa A'), findsOneWidget);
      expect(find.text('25% concluído'), findsOneWidget);
      expect(find.text('1 de 4 cursos disponíveis concluídos'), findsOneWidget);
      expect(find.text('Continue aprendendo'), findsOneWidget);
      expect(find.text('Recomendado para você'), findsOneWidget);
      expect(find.text('5 Dias'), findsNothing);
    },
  );
  testWidgets(
    'catalog server search, media and discover filters reset page state',
    (tester) async {
      final repo = _Learning()..count = 52;
      await _show(tester, const ModulesScreen(), learning: repo);
      await tester.enterText(find.byType(TextField), 'Curso 51');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(LearningCard),
          matching: find.text('Curso 51 da empresa a'),
        ),
        findsOneWidget,
      );
      expect(repo.calls.last.search, 'Curso 51');
      await tester.tap(find.text('Vídeos'));
      await tester.pumpAndSettle();
      expect(repo.calls.last.kind, 'video');
      await tester.tap(find.text('Descobrir'));
      await tester.pumpAndSettle();
      expect(repo.calls.last.state, 'not_started');
      expect(repo.calls.last.offset, 0);
    },
  );
  testWidgets('catalog lazily loads beyond 50 and resets on company change', (
    tester,
  ) async {
    final repo = _Learning()..count = 52;
    final container = await _show(
      tester,
      const ModulesScreen(),
      learning: repo,
    );
    await _visible(tester, find.text('Carregar mais cursos'));
    await tester.tap(find.text('Carregar mais cursos'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.offset, 50);
    await _visible(tester, find.text('Curso 51 da empresa a'));
    expect(find.text('Curso 51 da empresa a'), findsOneWidget);
    (container.read(sessionProvider.notifier) as _Session).switchCompany();
    await tester.pumpAndSettle();
    expect(repo.calls.last.company, 'b');
    expect(repo.calls.last.offset, 0);
    expect(find.text('Curso 51 da empresa a'), findsNothing);
  });
  testWidgets(
    'course continues the first unfinished video and returns to safe fallback',
    (tester) async {
      await _show(
        tester,
        const SizedBox(),
        location: '/funcionario/course/course-0',
      );
      expect(find.text('Em andamento · retomar aos 42s'), findsOneWidget);
      await _visible(tester, find.text('Continuar curso'));
      await tester.tap(find.text('Continuar curso'));
      await tester.pumpAndSettle();
      expect(find.text('Reproduzindo next'), findsOneWidget);
      await _show(
        tester,
        const SizedBox(),
        location: '/funcionario/course/course-0',
      );
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(ModulesScreen), findsOneWidget);
    },
  );
  testWidgets(
    'completed course issues a certificate without replaying progress',
    (tester) async {
      final repo = _Learning()
        ..lessonRows = const [
          EmployeeLesson(
            id: 'first',
            title: 'Introdução',
            moduleId: 'm1',
            moduleTitle: 'Módulo 1',
            kind: 'video',
            videoId: 'abcdefghijk',
            status: 'completed',
            positionSec: 100,
          ),
        ];
      await _show(
        tester,
        const CourseDetailScreen(courseId: 'course'),
        learning: repo,
      );
      await _visible(tester, find.text('Emitir certificado'));
      await tester.tap(find.text('Emitir certificado'));
      await tester.pumpAndSettle();
      expect(repo.issued, 1);
    },
  );
  testWidgets(
    'Rewards uses actual balance, confirms redemption and downloads actual certificate',
    (tester) async {
      final repo = _Learning();
      final docs = _Docs();
      await _show(tester, const RewardsScreen(), learning: repo, docs: docs);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('nível 3'), findsNothing);
      await tester.tap(find.byTooltip('Baixar certificado'));
      await tester.pumpAndSettle();
      expect(docs.downloaded?.code, 'AUD-123ABC');
      await _visible(tester, find.text('Resgatar'));
      await tester.tap(find.text('Resgatar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Resgatar').last);
      await tester.pumpAndSettle();
      expect(repo.redeemed, ['a:gift']);
      await _visible(tester, find.text('30'), delta: -180);
      expect(find.text('30'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown redemption response disables another attempt until refresh',
    (tester) async {
      final repo = _Learning()..redeemFailure = true;
      await _show(tester, const RewardsScreen(), learning: repo);
      await _visible(tester, find.text('Resgatar'));
      await tester.tap(find.text('Resgatar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Resgatar').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Resgatar'))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'profile exposes real department/stats and no fake settings switches',
    (tester) async {
      await _show(tester, const EmployeeProfileScreen());
      expect(find.text('Operações'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('English'), findsNothing);
      expect(find.text('Trocar perfil'), findsOneWidget);
    },
  );
  testWidgets(
    'employee profile editor reuses save flow and direct-route fallback',
    (tester) async {
      final profile = _Profile();
      await _show(
        tester,
        const SizedBox(),
        profile: profile,
        location: '/funcionario/perfil/edit',
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'Ana Atualizada',
      );
      await _visible(tester, find.text('Salvar perfil'));
      await tester.tap(find.text('Salvar perfil'));
      await tester.pumpAndSettle();
      expect(profile.saved?.fullName, 'Ana Atualizada');
      expect(find.byType(EmployeeProfileScreen), findsOneWidget);
    },
  );
  testWidgets('failed reads retry explicitly without polling', (tester) async {
    final repo = _Learning()..fail = true;
    await _show(tester, const EmployeeHomeScreen(), learning: repo);
    final reads = repo.summaryReads;
    await tester.pump(const Duration(seconds: 10));
    expect(repo.summaryReads, reads);
    repo.fail = false;
    await tester.tap(find.text('Tentar novamente').first);
    await tester.pumpAndSettle();
    expect(find.text('25% concluído'), findsOneWidget);
  });
  for (final width in [320.0, 418.0, 1000.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('all employee screens fit $width at scale $scale', (
        tester,
      ) async {
        for (final screen in [
          const EmployeeHomeScreen(),
          const ModulesScreen(),
          const CourseDetailScreen(courseId: 'course'),
          const EmployeeProgressScreen(),
          const RewardsScreen(),
          const EmployeeProfileScreen(),
        ]) {
          await _show(tester, screen, width: width, scale: scale);
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType}',
          );
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -550),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType} scrolled',
          );
        }
      });
    }
  }
  test(
    'certificate is generated locally as a real PDF with no external font fetch',
    () async {
      final bytes = await CertificateDocumentRepository().generate(
        EarnedCertificate(
          id: 'cert',
          code: 'AUD-123ABC',
          courseId: 'course',
          courseTitle: 'Segurança',
          companyName: 'Empresa',
          employeeName: 'Ana Silva',
          issuedAt: DateTime(2026, 10, 1),
        ),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(1000));
    },
  );
  test(
    'playback checkpoints normalize positions and completion remains monotonic',
    () async {
      final repo = _Progress();
      final progress = PlaybackProgress(
        repository: repo,
        companyId: 'a',
        lessonId: 'video',
        isCurrent: () => true,
        positionSec: 42,
        completed: false,
      );
      progress.update(Duration.zero, Duration.zero);
      expect(progress.positionSec, 42);
      progress.update(const Duration(seconds: 55), Duration.zero);
      expect(progress.positionSec, 55);
      expect(progress.completed, isFalse);
      progress.update(
        const Duration(seconds: 90),
        const Duration(seconds: 100),
      );
      await progress.save();
      expect(repo.writes.last.completed, isTrue);
      progress.update(
        const Duration(seconds: 20),
        const Duration(seconds: 100),
      );
      await progress.save(force: true);
      expect(repo.writes.last.completed, isTrue);
    },
  );
  test(
    'playback writes serialize and reject stale identity before writing',
    () async {
      final repo = _Progress()..pending = Completer<void>();
      var current = true;
      final progress = PlaybackProgress(
        repository: repo,
        companyId: 'a',
        lessonId: 'video',
        isCurrent: () => current,
        positionSec: 0,
        completed: false,
      );
      progress.update(
        const Duration(seconds: 20),
        const Duration(seconds: 100),
      );
      final first = progress.save();
      await Future<void>.delayed(Duration.zero);
      progress.update(
        const Duration(seconds: 50),
        const Duration(seconds: 100),
      );
      final second = progress.save();
      expect(repo.writes.length, 1);
      repo.pending!.complete();
      await Future.wait([first, second]);
      expect(repo.writes.length, 2);
      expect(repo.writes.last.position, 50);
      current = false;
      await expectLater(progress.save(force: true), throwsStateError);
      expect(repo.writes.length, 2);
    },
  );
  test(
    'failed checkpoint remains retryable and never claims persistence',
    () async {
      final repo = _Progress()..fail = true;
      final progress = PlaybackProgress(
        repository: repo,
        companyId: 'a',
        lessonId: 'video',
        isCurrent: () => true,
        positionSec: 0,
        completed: false,
      );
      progress.update(
        const Duration(seconds: 20),
        const Duration(seconds: 100),
      );
      await expectLater(progress.save(), throwsStateError);
      expect(progress.needsCheckpoint, isTrue);
      repo.fail = false;
      await progress.save();
      expect(progress.needsCheckpoint, isFalse);
    },
  );
  testWidgets('unavailable direct player route never initializes YouTube', (
    tester,
  ) async {
    final repo = _Learning()..blocked = true;
    await _show(
      tester,
      const EmployeePlayerScreen(courseId: 'course', lessonId: 'video'),
      learning: repo,
    );
    expect(find.textContaining('Aula indisponível'), findsOneWidget);
  });
  testWidgets(
    'real router restores protected deep links after session loading',
    (tester) async {
      final pending = Completer<AppSession?>();
      final repo = _Learning();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => _SlowSession(pending)),
          employeeLearningRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const EducaDorApp(),
        ),
      );
      final router = container.read(routerProvider);
      router.go('/funcionario/course/course');
      await tester.pump();
      pending.complete(
        const AppSession(user: _user, contexts: [_a], active: _a),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/funcionario/course/course',
      );
      expect(find.byType(CourseDetailScreen), findsOneWidget);
      final popped = router.push<void>('/funcionario/course/course-other');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/funcionario/course/course-other',
      );
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await popped;
      expect(
        router.routeInformationProvider.value.uri.path,
        '/funcionario/course/course',
      );
    },
  );
}

class _SlowSession extends SessionController {
  final Completer<AppSession?> pending;
  _SlowSession(this.pending);
  @override
  Future<AppSession?> build() => pending.future;
}
