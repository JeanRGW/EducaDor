import 'dart:async';

import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/auth/invite_forms.dart';
import 'package:educador/features/company/completion_screen.dart';
import 'package:educador/features/company/managers_screen.dart';
import 'package:educador/features/company/screens.dart';
import 'package:educador/features/company/widgets.dart';
import 'package:educador/shared/widgets/admin_styles.dart';
import 'package:educador/shared/widgets/charts.dart';
import 'package:educador/shared/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _context = AccessContext(
  role: Role.empresa,
  companyId: 'company-a',
  companyName: 'Grupo Santa Maria',
);
const _second = AccessContext(
  role: Role.empresa,
  companyId: 'company-b',
  companyName: 'Empresa B',
);
const _user = User(
  id: 'manager',
  fullName: 'Ana Silva',
  email: 'ana@example.test',
  initials: 'AS',
);

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async => const AppSession(
    user: _user,
    contexts: [_context, _second],
    active: _context,
  );

  void switchTo(AccessContext context) {
    state = AsyncData(
      AppSession(
        user: _user,
        contexts: const [_context, _second],
        active: context,
      ),
    );
  }
}

Employee _employee(
  int index, {
  double percent = 85,
  bool hasCompletion = true,
}) => Employee(
  id: 'employee-$index',
  fullName: index == 0 ? 'Roberto Silva' : 'Pessoa $index',
  initials: 'RS',
  email: 'person$index@example.test',
  department: index == 0 ? 'RH' : 'TI',
  jobTitle: 'Analista',
  phone: '',
  birthDate: '',
  address: '',
  status: EmployeeStatus.active,
  completionPct: percent,
  hasCompletion: hasCompletion,
  lastActivity: '',
);

class _Employees extends EmployeeRepository {
  List<Employee> rows = [
    _employee(0),
    _employee(1, percent: 40),
    _employee(2, percent: 0, hasCompletion: false),
  ];
  final calls = <String>[];
  bool fail = false;
  Completer<List<Employee>>? pending;
  @override
  Future<List<Employee>> all(String companyId) async {
    calls.add(companyId);
    if (fail) throw StateError('Offline');
    if (pending != null) return pending!.future;
    return companyId == 'company-a' ? rows : [_employee(10)];
  }
}

class _Reports extends ReportRepository {
  final calls = <String>[];
  bool fail = false;
  bool paginate = false;
  double? percent = 82.4;
  @override
  Future<double?> completion(String companyId) async {
    calls.add(companyId);
    if (fail) throw StateError('Offline');
    return percent;
  }

  @override
  Future<List<MapEntry<String, double?>>> departmentCompletion(
    String companyId, {
    int offset = 0,
  }) async {
    calls.add('$companyId:$offset');
    if (fail) throw StateError('Offline');
    if (paginate) {
      return [
        for (var i = offset; i < offset + (offset == 0 ? 50 : 1); i++)
          MapEntry('Departamento $i', 80),
      ];
    }
    return const [
      MapEntry('TI', 92),
      MapEntry('RH', 60),
      MapEntry('Sem departamento', null),
    ];
  }
}

class _Companies extends CompanyRepository {
  final calls = <String>[];
  @override
  Future<Company> byId(String id) async {
    calls.add(id);
    return Company(
      id: id,
      name: id == 'company-a' ? _context.companyName : _second.companyName,
      cnpj: '12.345.678/0001-90',
      responsibleName: '',
      email: '',
      phone: '',
      address: '',
      city: '',
      state: '',
      field: '',
      employeeCount: -1,
      active: true,
      registeredAt: '',
      initials: 'GSM',
    );
  }
}

class _Invites extends InvitationRepository {
  ({String? company, String? department, String? jobTitle})? request;
  @override
  Future<List<PendingInvitation>> pending({
    Role? role,
    String? companyId,
  }) async => [];
  @override
  Future<String> invite({
    required Role role,
    required String name,
    required String email,
    String? companyId,
    Map<String, String>? company,
    String? department,
    String? jobTitle,
  }) async {
    request = (company: companyId, department: department, jobTitle: jobTitle);
    return 'https://example.test/one-time-link';
  }
}

class _People extends PeopleRepository {
  @override
  Future<List<User>> companyManagers(String companyId) async => [_user];
}

class _Content extends ContentRepository {
  @override
  Future<List<ManagedContent>> catalog({
    String search = '',
    String? kind,
    int offset = 0,
  }) async => const [
    ManagedContent(
      id: 'course',
      title: 'Treinamento de segurança',
      kind: 'course',
      platformEnabled: true,
      allCompanies: true,
      companyEnabled: true,
      companyIds: [],
      companyCount: 1,
      lessonCount: 3,
      completionPct: 85,
    ),
  ];
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  Widget screen, {
  double width = 418,
  double scale = 1,
  String initialLocation = '/',
  _Employees? employees,
  _Reports? reports,
  _Companies? companies,
  _Invites? invites,
}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(_Session.new),
      employeeRepositoryProvider.overrideWithValue(employees ?? _Employees()),
      reportRepositoryProvider.overrideWithValue(reports ?? _Reports()),
      companyRepositoryProvider.overrideWithValue(companies ?? _Companies()),
      invitationRepositoryProvider.overrideWithValue(invites ?? _Invites()),
      peopleRepositoryProvider.overrideWithValue(_People()),
      contentRepositoryProvider.overrideWithValue(_Content()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.future);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/empresa/funcionarios',
        builder: (_, _) => const EmployeesScreen(),
      ),
      GoRoute(
        path: '/empresa/employee/add',
        builder: (_, _) => const AddEmployeeScreen(),
      ),
      GoRoute(
        path: '/empresa/gestores',
        builder: (_, _) => const CompanyManagersScreen(),
      ),
      GoRoute(
        path: '/empresa/manager/add',
        builder: (_, _) => const AddCompanyManagerScreen(),
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

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      AppFonts.inter: 'assets/fonts/Inter-Variable.ttf',
      AppFonts.outfit: 'assets/fonts/Outfit-Variable.ttf',
    }.entries) {
      final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });

  for (final (route, destination, screenType) in [
    ('/empresa/employee/add', '/empresa/funcionarios', EmployeesScreen),
    ('/empresa/manager/add', '/empresa/gestores', CompanyManagersScreen),
  ]) {
    testWidgets('direct invitation $route returns safely to $destination', (
      tester,
    ) async {
      await _show(tester, const SizedBox(), initialLocation: route);
      final router = GoRouter.of(
        tester.element(find.byType(InvitePersonScreen)),
      );
      expect(router.canPop(), isFalse);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, destination);
      expect(find.byType(screenType), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pushed invitation $route pops back to its caller', (
      tester,
    ) async {
      await _show(tester, const CompanyProfileScreen());
      final router = GoRouter.of(
        tester.element(find.byType(CompanyProfileScreen)),
      );
      final popped = router.push<void>(route);
      await tester.pumpAndSettle();
      expect(router.canPop(), isTrue);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await popped;

      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.byType(CompanyProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'direct invitation $route exits safely after creating an invite',
      (tester) async {
        final invites = _Invites();
        await _show(
          tester,
          const SizedBox(),
          initialLocation: route,
          invites: invites,
        );
        final router = GoRouter.of(
          tester.element(find.byType(InvitePersonScreen)),
        );
        for (final (label, value) in [
          ('NOME COMPLETO', 'Pessoa Convidada'),
          ('EMAIL', 'person@example.test'),
        ]) {
          await tester.enterText(
            find.descendant(
              of: find.widgetWithText(FormFieldLabel, label),
              matching: find.byType(TextFormField),
            ),
            value,
          );
        }
        await tester.tap(find.text('Criar convite'));
        await tester.pumpAndSettle();
        expect(find.text('Convite criado'), findsOneWidget);
        await tester.tap(find.text('Fechar sem copiar'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Fechar sem copiar'));
        await tester.pumpAndSettle();

        expect(invites.request?.company, 'company-a');
        expect(router.routeInformationProvider.value.uri.path, destination);
        expect(find.byType(screenType), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'dashboard matches prototype hierarchy without fabricated metrics',
    (tester) async {
      await _show(tester, const CompanyDashboardScreen());
      expect(find.text(_context.companyName), findsOneWidget);
      expect(find.text('82,4%'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Em breve'), findsNWidgets(2));
      expect(find.byType(LineChart), findsNothing);
      expect(
        tester.widget<Text>(find.text('Total de funcionários')).style,
        AdminStyles.fieldLabel,
      );
      final employeeMetric = find.ancestor(
        of: find.text('Total de funcionários'),
        matching: find.byType(AppCard),
      );
      final courseMetric = find.ancestor(
        of: find.text('Cursos ativos'),
        matching: find.byType(AppCard),
      );
      expect(
        tester.getTopLeft(employeeMetric).dy,
        tester.getTopLeft(courseMetric).dy,
      );
      expect(tester.getSize(employeeMetric).height, greaterThanOrEqualTo(110));
      expect(tester.getTopLeft(employeeMetric).dx, 16);
      await _scrollTo(tester, find.text('Destaques'));
      expect(find.text('Roberto Silva (RH)'), findsOneWidget);
      expect(find.textContaining('Pegou recompensa'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'employees keep prototype cards, honest unknowns and working search',
    (tester) async {
      await _show(tester, const EmployeesScreen());
      expect(tester.getSize(find.byType(TextField)).height, closeTo(36, 2));
      expect(find.text('Ativos (3)'), findsOneWidget);
      expect(find.text('De licença'), findsOneWidget);
      expect(
        find.byTooltip('Situação de licença ainda não disponível.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .backgroundColor,
        AppColors.successDarkGreen,
      );
      final progress = find.byType(ProgressBar).first;
      final caption = find.text('Progresso de Conclusão').first;
      expect(
        tester.getTopLeft(progress).dy,
        lessThan(tester.getTopLeft(caption).dy),
      );
      expect(
        tester.widget<ProgressBar>(progress).color,
        AppColors.successDarkGreen,
      );
      expect(find.text('Última atividade: não disponível'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'RH');
      await tester.pumpAndSettle();
      expect(find.text('Roberto Silva'), findsOneWidget);
      expect(find.text('Pessoa 1'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Pessoa 2');
      await tester.pumpAndSettle();
      expect(find.text('Sem dados'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile uses company identity and preserves manager entry point',
    (tester) async {
      final companies = _Companies();
      await _show(tester, const CompanyProfileScreen(), companies: companies);
      expect(companies.calls, ['company-a']);
      final avatar = tester.widget<CompanyAvatar>(find.byType(CompanyAvatar));
      expect(avatar.size, 72);
      expect(avatar.outlined, isTrue);
      expect(avatar.initials, 'GSM');
      expect(find.text('CNPJ: 12.345.678/0001-90'), findsOneWidget);
      expect(find.text('3 Funcionários'), findsOneWidget);
      expect(find.text('Trocar perfil'), findsOneWidget);
      expect(find.textContaining('24/7'), findsNothing);
      await tester.tap(find.text('Gestores da empresa'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanyManagersScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reports use existing department data and clearly defer unavailable features',
    (tester) async {
      final reports = _Reports();
      await _show(tester, const CompanyCompletionScreen(), reports: reports);
      expect(reports.calls, ['company-a:0']);
      expect(find.text('Relatórios'), findsOneWidget);
      expect(
        find.text('Conclusão atual · sem filtro de período'),
        findsOneWidget,
      );
      expect(find.text('92%'), findsOneWidget);
      expect(
        find.text('Sem departamento: sem dados de conclusão'),
        findsOneWidget,
      );
      expect(find.text('Indicadores disponíveis em breve.'), findsOneWidget);
      expect(find.textContaining('PALS'), findsNothing);
      final csv = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exportar dados em CSV'),
      );
      expect(csv.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reports paginate and switching company drops old pages', (
    tester,
  ) async {
    final reports = _Reports()..paginate = true;
    final container = await _show(
      tester,
      const CompanyCompletionScreen(),
      reports: reports,
    );
    await _scrollTo(tester, find.text('Carregar mais departamentos'));
    await tester.tap(find.text('Carregar mais departamentos'));
    await tester.pumpAndSettle();
    expect(reports.calls, ['company-a:0', 'company-a:50']);
    (container.read(sessionProvider.notifier) as _Session).switchTo(_second);
    await tester.pumpAndSettle();
    expect(reports.calls.last, 'company-b:0');
    expect(reports.calls, isNot(contains('company-b:50')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching company discards employee search results from prior scope',
    (tester) async {
      final employees = _Employees();
      final container = await _show(
        tester,
        const EmployeesScreen(),
        employees: employees,
      );
      expect(find.text('Roberto Silva'), findsOneWidget);
      (container.read(sessionProvider.notifier) as _Session).switchTo(_second);
      await tester.pumpAndSettle();
      expect(find.text('Roberto Silva'), findsNothing);
      expect(find.text('Pessoa 10'), findsOneWidget);
      expect(employees.calls, ['company-a', 'company-b']);
    },
  );

  testWidgets(
    'a 50-row employee result is not presented as an exact company count',
    (tester) async {
      final employees = _Employees()
        ..rows = [for (var i = 0; i < 50; i++) _employee(i)];
      await _show(tester, const CompanyDashboardScreen(), employees: employees);
      expect(find.text('50+'), findsOneWidget);
      expect(find.text('Lista limitada a 50'), findsOneWidget);
      await _show(tester, const EmployeesScreen(), employees: employees);
      expect(
        find.textContaining('A pesquisa se aplica a esta lista.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'employee invitation keeps scoped onboarding and only supported fields',
    (tester) async {
      final invites = _Invites();
      await _show(tester, const AddEmployeeScreen(), invites: invites);
      expect(find.text('Convidar funcionário'), findsOneWidget);
      expect(find.text('DATA DE NASCIMENTO'), findsNothing);
      expect(find.text('NUMERO'), findsNothing);
      for (final (label, value) in [
        ('NOME COMPLETO', 'Pessoa Convidada'),
        ('EMAIL', 'person@example.test'),
        ('DEPARTAMENTO', 'Obras'),
        ('CARGO / ESPECIALIDADE', 'Analista'),
      ]) {
        await tester.enterText(
          find.descendant(
            of: find.widgetWithText(FormFieldLabel, label),
            matching: find.byType(TextFormField),
          ),
          value,
        );
      }
      await tester.tap(find.text('Criar convite'));
      await tester.pumpAndSettle();
      expect(invites.request, (
        company: 'company-a',
        department: 'Obras',
        jobTitle: 'Analista',
      ));
      expect(find.text('Convite criado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dashboard errors retry explicitly and do not poll', (
    tester,
  ) async {
    final employees = _Employees()..fail = true;
    final reports = _Reports()..fail = true;
    await _show(
      tester,
      const CompanyDashboardScreen(),
      employees: employees,
      reports: reports,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(employees.calls, ['company-a']);
    employees.fail = reports.fail = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('82,4%'), findsOneWidget);
    expect(employees.calls.length, 2);
  });

  for (final width in [320.0, 418.0, 1000.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('company screens fit width $width at text scale $scale', (
        tester,
      ) async {
        for (final screen in [
          const CompanyDashboardScreen(),
          const EmployeesScreen(),
          const CompanyCompletionScreen(),
          const CompanyProfileScreen(),
          const AddEmployeeScreen(),
          const CompanyManagersScreen(),
          const CompanyContentScreen(),
        ]) {
          await _show(tester, screen, width: width, scale: scale);
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType}',
          );
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType} scrolled',
          );
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
