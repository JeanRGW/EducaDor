import 'package:educador/app/theme.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/content/course_edit_screen.dart';
import 'package:educador/features/gestor/company_detail_screen.dart';
import 'package:educador/features/gestor/managers_screen.dart';
import 'package:educador/features/gestor/profile_edit_screen.dart';
import 'package:educador/features/company/screens.dart';
import 'package:educador/shared/widgets/admin_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _user = User(
  id: 'me',
  fullName: 'Ana Silva',
  email: 'ana@example.test',
  initials: 'AS',
);
const _gestor = AccessContext(role: Role.gestor, companyName: 'Plataforma');
const _empresa = AccessContext(
  role: Role.empresa,
  companyId: 'company',
  companyName: 'Empresa',
);

class _Session extends SessionController {
  int reloads = 0;
  bool fail = false;
  AppSession? get currentSession => state.value;
  @override
  Future<AppSession?> build() async => const AppSession(
    user: _user,
    contexts: [_gestor, _empresa],
    active: _gestor,
  );
  @override
  Future<AppSession?> reload() async {
    reloads++;
    if (fail) throw StateError('Offline');
    return state.value;
  }

  @override
  Future<void> select(AccessContext context) async {
    state = AsyncData(
      AppSession(
        user: _user,
        contexts: const [_gestor, _empresa],
        active: context,
      ),
    );
    sessionRefresh.refresh();
  }
}

class _Companies extends CompanyRepository {
  bool fail = false;
  Map<String, String>? saved;
  final activeWrites = <bool>[];
  @override
  Future<Company> byId(String id) async => const Company(
    id: 'company',
    name: 'Empresa original',
    cnpj: '123',
    responsibleName: 'Responsável',
    email: 'contact@example.test',
    phone: '123',
    address: 'Rua A',
    city: 'BH',
    state: 'MG',
    field: 'Saúde',
    employeeCount: 3,
    active: true,
    registeredAt: '2026-10-01',
    initials: 'EO',
  );
  @override
  Future<void> update(String id, Map<String, String> fields) async {
    if (fail) throw StateError('Offline');
    saved = fields;
  }

  @override
  Future<void> setActive(String id, bool active) async {
    activeWrites.add(active);
  }

  @override
  Future<List<CompanyOption>> options({
    int offset = 0,
    String search = '',
  }) async {
    if (offset > 0) return [];
    return const [
      CompanyOption(id: 'a', name: 'Santa Maria', active: true),
      CompanyOption(id: 'b', name: 'Outra Empresa', active: true),
    ];
  }

  @override
  Future<CompanyPage> page({
    String search = '',
    bool? active,
    int offset = 0,
  }) async => const CompanyPage(
    items: [
      Company(
        id: 'company',
        name: 'Empresa original',
        cnpj: '123',
        responsibleName: 'Responsável',
        email: 'contact@example.test',
        phone: '123',
        address: 'Rua A',
        city: 'BH',
        state: 'MG',
        field: 'Saúde',
        employeeCount: 3,
        active: true,
        registeredAt: '2026-10-01',
        initials: 'EO',
      ),
    ],
    activeCount: 1,
    inactiveCount: 0,
  );
}

class _People extends PeopleRepository {
  String? revoked;
  String? scope;
  bool reject = false;
  bool self = false;
  bool paginate = false;
  final offsets = <int>[];
  @override
  Future<List<User>> managers({
    String? companyId,
    String search = '',
    int offset = 0,
  }) async {
    offsets.add(offset);
    if (search.isNotEmpty) return [];
    if (paginate) {
      return [
        for (var i = offset; i < (offset == 0 ? 50 : 51); i++)
          User(
            id: 'user-$i',
            fullName: 'Gestor $i',
            email: 'user$i@example.test',
            initials: 'GA',
          ),
      ];
    }
    if (revoked != null) return [];
    return [
      User(
        id: self ? 'me' : 'other',
        fullName: 'Gestor ativo',
        email: 'other@example.test',
        initials: 'GA',
      ),
    ];
  }

  @override
  Future<void> revokeAccess(String userId, {String? companyId}) async {
    if (reject) {
      throw const ManagementException(
        'A empresa precisa manter pelo menos um gestor.',
      );
    }
    revoked = userId;
    scope = companyId;
  }
}

class _Profiles extends ProfileRepository {
  OwnProfile? saved;
  int writes = 0;
  @override
  Future<OwnProfile> own() async => const OwnProfile(
    fullName: 'Ana Silva',
    email: 'ana@example.test',
    phone: '123',
    address: 'Rua A',
  );
  @override
  Future<void> update(OwnProfile profile) async {
    saved = profile;
    writes++;
  }
}

class _Content extends ContentRepository {
  bool fail = false;
  bool failAudience = false;
  bool failLessons = false;
  String? savedTitle;
  String? savedCover;
  String? savedResponsible;
  String? lessonId;
  String? videoId;
  ContentAudience currentAudience = const ContentAudience(
    allCompanies: false,
    companyIds: ['a'],
  );
  ContentAudience? savedAudience;
  @override
  Future<EditableCourse> detail(String id) async => const EditableCourse(
    id: 'course',
    title: 'Curso original',
    description: 'Descrição original',
    coverKey: 'legacy.webp',
    responsible: ProfessionalOption(id: 'author', name: 'Autora'),
    platformEnabled: false,
    allCompanies: false,
  );
  @override
  Future<List<EditableLesson>> editableLessons(
    String courseId, {
    int offset = 0,
  }) async {
    if (failLessons) throw StateError('Offline');
    return const [
      EditableLesson(
        id: 'lesson',
        title: 'Aula original',
        moduleTitle: 'Módulo original',
        kind: 'video',
        videoId: 'dQw4w9WgXcQ',
      ),
    ];
  }

  @override
  Future<void> updateMetadata(
    String id, {
    required String title,
    required String description,
    String? coverKey,
    String? responsibleId,
  }) async {
    if (fail) throw StateError('Offline');
    savedTitle = title;
    savedCover = coverKey;
    savedResponsible = responsibleId;
  }

  @override
  Future<void> updateLesson(
    String id, {
    required String moduleTitle,
    required String title,
    String? videoId,
  }) async {
    lessonId = id;
    this.videoId = videoId;
  }

  @override
  Future<ContentAudience> audience(String courseId) async {
    if (failAudience) throw StateError('Offline');
    return currentAudience;
  }

  @override
  Future<void> setAudience(String courseId, ContentAudience audience) async {
    if (failAudience) throw StateError('Offline');
    savedAudience = audience;
    currentAudience = audience;
  }
}

class _Invites extends InvitationRepository {
  @override
  Future<List<PendingInvitation>> pending({
    Role? role,
    String? companyId,
  }) async => [];
}

Future<_Session> _show(
  WidgetTester tester,
  Widget screen, {
  _Companies? companies,
  _People? people,
  _Profiles? profiles,
  _Content? content,
  double width = 390,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/detail',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Voltar')),
        routes: [GoRoute(path: 'detail', builder: (_, _) => screen)],
      ),
      GoRoute(
        path: '/contexts',
        builder: (_, _) => const Scaffold(body: Text('Escolher perfil')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        invitationRepositoryProvider.overrideWithValue(_Invites()),
        companyRepositoryProvider.overrideWithValue(companies ?? _Companies()),
        if (people != null) peopleRepositoryProvider.overrideWithValue(people),
        if (profiles != null)
          profileRepositoryProvider.overrideWithValue(profiles),
        if (content != null)
          contentRepositoryProvider.overrideWithValue(content),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(screen.runtimeType)),
  );
  await container.read(sessionProvider.future);
  return container.read(sessionProvider.notifier) as _Session;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1000.0]) {
    testWidgets('company editor matches create layout at width $width', (
      tester,
    ) async {
      await _show(
        tester,
        const CompanyDetailScreen(companyId: 'company'),
        companies: _Companies(),
        width: width,
      );
      final name = tester.widget<TextField>(
        find.descendant(
          of: _field('Nome da empresa'),
          matching: find.byType(TextField),
        ),
      );
      expect(name.decoration!.labelText, isNull);
      expect(
        tester.getRect(find.text('Nome da empresa').first).bottom,
        lessThan(tester.getRect(_field('Nome da empresa')).top),
      );
      expect(find.text('Registro: 01 out 2026'), findsOneWidget);
      final pause = find.widgetWithText(OutlinedButton, 'Pausar empresa');
      final managers = find.widgetWithText(
        OutlinedButton,
        'Gerenciar gestores da empresa',
      );
      expect(
        OutlinedButtonTheme.of(
          tester.element(pause),
        ).style!.foregroundColor!.resolve({}),
        AppColors.successDarkGreen,
      );
      final pauseRect = tester.getRect(pause);
      final managersRect = tester.getRect(managers);
      expect(pauseRect.overlaps(managersRect), isFalse);

      for (final row in [
        ['E-mail de contato', 'Telefone'],
        ['Cidade', 'Estado'],
      ]) {
        await tester.scrollUntilVisible(
          _field(row.last),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final first = tester.getRect(_field(row.first));
        final second = tester.getRect(_field(row.last));
        if (width == 320) {
          expect(second.top, greaterThan(first.bottom));
          expect(second.left, first.left);
        } else {
          expect(
            tester.getRect(find.text(row.last).first).top,
            tester.getRect(find.text(row.first).first).top,
          );
          expect(second.left, greaterThan(first.right));
          if (row.first == 'Cidade') {
            expect(first.width, closeTo(second.width * 3, 0.01));
          }
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('direct management routes have safe back destinations', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        invitationRepositoryProvider.overrideWithValue(_Invites()),
        companyRepositoryProvider.overrideWithValue(_Companies()),
        peopleRepositoryProvider.overrideWithValue(_People()),
        profileRepositoryProvider.overrideWithValue(_Profiles()),
        contentRepositoryProvider.overrideWithValue(_Content()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    final router = container.read(routerProvider);
    router.go('/gestor/company/company');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    for (final entry in {
      '/gestor/company/company': '/gestor/empresas',
      '/gestor/company/company/gestores': '/gestor/company/company',
      '/gestor/gestores': '/gestor/perfil',
      '/gestor/perfil/edit': '/gestor/perfil',
      '/gestor/course/course': '/gestor/conteudo',
    }.entries) {
      router.go(entry.key);
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, entry.value);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'profile save falls back on direct entry but pops a pushed page',
    (tester) async {
      final profiles = _Profiles();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(_Session.new),
          invitationRepositoryProvider.overrideWithValue(_Invites()),
          companyRepositoryProvider.overrideWithValue(_Companies()),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      final router = container.read(routerProvider);
      router.go('/gestor/perfil/edit');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
      await _tap(tester, find.text('Salvar perfil'));
      expect(router.routeInformationProvider.value.uri.path, '/gestor/perfil');
      expect(profiles.writes, 1);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      router.go('/gestor/company/company');
      await tester.pumpAndSettle();
      final saved = router.push('/gestor/perfil/edit');
      await tester.pumpAndSettle();
      expect(router.canPop(), isTrue);
      final saveButton = find.widgetWithText(FilledButton, 'Salvar perfil');
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      await saved;
      expect(find.byType(CompanyDetailScreen), findsOneWidget);
      expect(profiles.writes, 2);
      final back = router.push('/gestor/perfil/edit');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await back;
      expect(find.byType(CompanyDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all new routes resolve and a company context cannot enter them',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(_Session.new),
          invitationRepositoryProvider.overrideWithValue(_Invites()),
          companyRepositoryProvider.overrideWithValue(_Companies()),
          peopleRepositoryProvider.overrideWithValue(_People()),
          profileRepositoryProvider.overrideWithValue(_Profiles()),
          contentRepositoryProvider.overrideWithValue(_Content()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      final router = container.read(routerProvider);
      router.go('/gestor/company/company');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final destinations = <String, Type>{
        '/gestor/company/company': CompanyDetailScreen,
        '/gestor/company/company/gestores': GestorManagersScreen,
        '/gestor/gestores': GestorManagersScreen,
        '/gestor/perfil/edit': ProfileEditScreen,
        '/gestor/course/course': CourseEditScreen,
      };
      for (final destination in destinations.entries) {
        router.go(destination.key);
        await tester.pumpAndSettle();
        expect(find.byType(destination.value), findsOneWidget);
      }
      await container.read(sessionProvider.notifier).select(_empresa);
      for (final destination in destinations.keys) {
        router.go(destination);
        await tester.pumpAndSettle();
        expect(find.byType(CompanyDashboardScreen), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('company edits preserve fields and refresh the session', (
    tester,
  ) async {
    final repo = _Companies();
    final session = await _show(
      tester,
      const CompanyDetailScreen(companyId: 'company'),
      companies: repo,
    );
    await tester.enterText(_field('Nome da empresa'), 'Empresa editada');
    await _tap(tester, find.text('Salvar dados da empresa'));
    expect(repo.saved!['name'], 'Empresa editada');
    expect(repo.saved!['address'], 'Rua A');
    expect(repo.saved!.containsKey('active'), isFalse);
    expect(session.reloads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('company pause and reactivation require confirmation', (
    tester,
  ) async {
    final repo = _Companies();
    await _show(
      tester,
      const CompanyDetailScreen(companyId: 'company'),
      companies: repo,
    );
    await _tap(tester, find.text('Pausar empresa'));
    await _tap(tester, find.text('Cancelar'));
    expect(repo.activeWrites, isEmpty);
    await _tap(tester, find.text('Pausar empresa'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Pausar empresa'));
    expect(repo.activeWrites, [false]);
    await _tap(tester, find.text('Reativar empresa'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Reativar empresa'));
    expect(repo.activeWrites, [false, true]);
  });

  testWidgets('company save failure retains the draft', (tester) async {
    final repo = _Companies()..fail = true;
    await _show(
      tester,
      const CompanyDetailScreen(companyId: 'company'),
      companies: repo,
    );
    await tester.enterText(_field('Nome da empresa'), 'Rascunho');
    await _tap(tester, find.text('Salvar dados da empresa'));
    expect(repo.saved, isNull);
    await tester.ensureVisible(_field('Nome da empresa'));
    expect(
      tester.widget<TextFormField>(_field('Nome da empresa')).controller!.text,
      'Rascunho',
    );
  });

  testWidgets(
    'company manager removal is scoped and last-gestor errors are shown',
    (tester) async {
      final repo = _People()..reject = true;
      await _show(
        tester,
        const GestorManagersScreen(companyId: 'company'),
        people: repo,
      );
      await _tap(tester, find.text('Remover acesso'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Remover acesso'));
      expect(
        find.text('A empresa precisa manter pelo menos um gestor.'),
        findsOneWidget,
      );
      expect(find.text('Gestor ativo'), findsOneWidget);
      repo.reject = false;
      await _tap(tester, find.text('Remover acesso'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Remover acesso'));
      expect(repo.revoked, 'other');
      expect(repo.scope, 'company');
      expect(find.text('Gestor ativo'), findsNothing);
    },
  );

  testWidgets('manager directory loads later pages and resets on search', (
    tester,
  ) async {
    final repo = _People()..paginate = true;
    await _show(tester, const GestorManagersScreen(), people: repo);
    await tester.scrollUntilVisible(
      find.text('Carregar mais gestores'),
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await _tap(tester, find.text('Carregar mais gestores'));
    expect(repo.offsets, [0, 50]);
    await tester.scrollUntilVisible(
      find.text('Pesquisar nome ou e-mail'),
      -600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.enterText(find.byType(TextField).first, 'unmatched');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.offsets, [0, 50, 0]);
    expect(find.text('Nenhum gestor encontrado.'), findsOneWidget);
  });

  testWidgets(
    'self-revocation discards privileged context even when refresh fails',
    (tester) async {
      final repo = _People()..self = true;
      final session = await _show(
        tester,
        const GestorManagersScreen(),
        people: repo,
      );
      session.fail = true;
      await _tap(tester, find.text('Remover acesso'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Remover acesso'));
      expect(session.currentSession!.active, isNull);
      expect(session.currentSession!.contexts, [_empresa]);
      expect(session.reloads, 1);
    },
  );

  testWidgets('profile refresh retry does not write profile twice', (
    tester,
  ) async {
    final repo = _Profiles();
    final session = await _show(
      tester,
      const ProfileEditScreen(),
      profiles: repo,
    );
    session.fail = true;
    await tester.enterText(_field('Nome completo'), 'Ana Editada');
    await _tap(tester, find.text('Salvar perfil'));
    expect(repo.saved!.fullName, 'Ana Editada');
    expect(repo.saved!.email, 'ana@example.test');
    expect(find.text('Atualizar sessão'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(_field('Nome completo')).enabled,
      isFalse,
    );
    session.fail = false;
    await _tap(tester, find.text('Atualizar sessão'));
    expect(repo.writes, 1);
    expect(session.reloads, 2);
  });

  testWidgets('course metadata save preserves cover and responsible', (
    tester,
  ) async {
    final repo = _Content();
    await _show(
      tester,
      const CourseEditScreen(courseId: 'course'),
      content: repo,
    );
    await tester.enterText(_field('Título da trilha'), 'Curso editado');
    await _tap(tester, find.text('Salvar dados da trilha'));
    expect(repo.savedTitle, 'Curso editado');
    expect(repo.savedCover, 'legacy.webp');
    expect(repo.savedResponsible, 'author');
    expect(find.text('Pausada pela plataforma'), findsNothing);
    expect(find.text('Empresas selecionadas'), findsWidgets);
  });

  testWidgets('course editor uses labeled fields and teal selectors', (
    tester,
  ) async {
    await _show(
      tester,
      const CourseEditScreen(courseId: 'course'),
      content: _Content(),
    );
    final title = tester.widget<TextField>(
      find.descendant(
        of: _field('Título da trilha'),
        matching: find.byType(TextField),
      ),
    );
    expect(title.decoration!.labelText, isNull);
    expect(find.text('Imagem de capa'), findsOneWidget);
    expect(find.text('Profissional responsável'), findsOneWidget);
    final responsible = find.widgetWithText(OutlinedButton, 'Autora');
    expect(responsible, findsOneWidget);
    final cover = find.widgetWithText(OutlinedButton, 'Alterar imagem de capa');
    expect(
      OutlinedButtonTheme.of(
        tester.element(cover),
      ).style!.foregroundColor!.resolve({}),
      AppColors.successDarkGreen,
    );
    expect(find.text('Acesso liberado'), findsNothing);
    expect(find.text('Pausada pela plataforma'), findsNothing);
    expect(find.textContaining('Editar não altera'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Módulos e aulas'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Módulos e aulas')).style,
      AdminStyles.cardTitle,
    );
    expect(
      tester.widget<Text>(find.text('Aula original')).style,
      AdminStyles.cardTitle,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('course lesson error keeps a styled working retry', (
    tester,
  ) async {
    final repo = _Content()..failLessons = true;
    await _show(
      tester,
      const CourseEditScreen(courseId: 'course'),
      content: repo,
    );
    await tester.scrollUntilVisible(
      find.text('Tentar novamente'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Não foi possível carregar aulas.')).style,
      AdminStyles.body,
    );
    repo.failLessons = false;
    await _tap(tester, find.text('Tentar novamente'));
    expect(find.text('Aula original'), findsOneWidget);
    expect(find.text('Não foi possível carregar aulas.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('course audience lives inside the edit screen', (tester) async {
    final repo = _Content();
    await _show(
      tester,
      const CourseEditScreen(courseId: 'course'),
      content: repo,
    );
    expect(find.text('Liberar para'), findsOneWidget);
    expect(find.text('Empresas selecionadas'), findsWidgets);
    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Empresas selecionadas'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Todas as empresas'), findsWidgets);
    await tester.tap(find.text('Outra Empresa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar seleção'));
    await tester.pumpAndSettle();
    expect(repo.savedAudience?.allCompanies, isFalse);
    expect(repo.savedAudience?.companyIds, ['a', 'b']);
    expect(find.text('2 empresas selecionadas'), findsOneWidget);
    expect(find.text('Público atualizado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'course metadata failures retain the draft and support removals',
    (tester) async {
      final repo = _Content()..fail = true;
      await _show(
        tester,
        const CourseEditScreen(courseId: 'course'),
        content: repo,
      );
      await tester.enterText(_field('Título da trilha'), 'Rascunho do curso');
      await _tap(tester, find.text('Salvar dados da trilha'));
      expect(repo.savedTitle, isNull);
      expect(
        tester
            .widget<TextFormField>(_field('Título da trilha'))
            .controller!
            .text,
        'Rascunho do curso',
      );
      repo.fail = false;
      await _tap(tester, find.text('Remover capa'));
      await _tap(tester, find.text('Remover responsável'));
      await _tap(tester, find.text('Salvar dados da trilha'));
      expect(repo.savedTitle, 'Rascunho do curso');
      expect(repo.savedCover, isNull);
      expect(repo.savedResponsible, isNull);
    },
  );

  testWidgets('video replacement validates YouTube and confirms preservation', (
    tester,
  ) async {
    final repo = _Content();
    await _show(
      tester,
      const CourseEditScreen(courseId: 'course'),
      content: repo,
    );
    await tester.scrollUntilVisible(
      find.text('Editar aula'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Editar aula'));
    await tester.enterText(_field('Vídeo do YouTube'), 'invalid');
    await _tap(tester, find.text('Salvar aula'));
    expect(find.text('Informe uma URL ou ID válido.'), findsOneWidget);
    expect(repo.lessonId, isNull);
    await tester.enterText(
      _field('Vídeo do YouTube'),
      'https://youtu.be/abcdefghijk',
    );
    await _tap(tester, find.text('Salvar aula'));
    await _tap(tester, find.text('Cancelar'));
    expect(repo.lessonId, isNull);
    await _tap(tester, find.text('Salvar aula'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Substituir vídeo'));
    expect(repo.lessonId, 'lesson');
    expect(repo.videoId, 'abcdefghijk');
    expect(tester.takeException(), isNull);
  });

  testWidgets('company card uses matching outlined actions', (tester) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        invitationRepositoryProvider.overrideWithValue(_Invites()),
        companyRepositoryProvider.overrideWithValue(_Companies()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    final router = container.read(routerProvider);
    router.go('/gestor/empresas');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Detalhes e edição'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Convidar gestor da empresa'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Editar'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Editar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile fields share labels and teal controls', (tester) async {
    await _show(tester, const ProfileEditScreen(), profiles: _Profiles());
    expect(find.text('E-mail de acesso'), findsOneWidget);
    expect(find.text('Dados pessoais'), findsOneWidget);
    expect(find.text('Data de nascimento'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Não informada'),
      findsOneWidget,
    );
    expect(find.text('Limpar data'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Salvar perfil'),
          )
          .style
          ?.backgroundColor
          ?.resolve({}),
      AppColors.successDarkGreen,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1000.0]) {
    testWidgets('management screens fit width $width with large text', (
      tester,
    ) async {
      for (final screen in [
        const CompanyDetailScreen(companyId: 'company'),
        const GestorManagersScreen(),
        const ProfileEditScreen(),
        const CourseEditScreen(courseId: 'course'),
      ]) {
        await _show(
          tester,
          screen,
          companies: _Companies(),
          people: _People(),
          profiles: _Profiles(),
          content: _Content(),
          width: width,
          textScale: 1.8,
        );
        expect(tester.takeException(), isNull);
        if (screen is CompanyDetailScreen) {
          for (final row in [
            ['E-mail de contato', 'Telefone'],
            ['Cidade', 'Estado'],
          ]) {
            await tester.scrollUntilVisible(
              _field(row.last),
              150,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(
              tester.getRect(_field(row.last)).top,
              greaterThan(tester.getRect(_field(row.first)).bottom),
            );
          }
          await tester.scrollUntilVisible(
            find.text('Salvar dados da empresa'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
