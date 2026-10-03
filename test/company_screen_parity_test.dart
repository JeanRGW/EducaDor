import 'dart:async';
import 'dart:ui' as ui;

import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/repositories/company_providers.dart';
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
  DateTime? activityAt,
  EmployeeStatus status = EmployeeStatus.unknown,
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
  status: status,
  completionPct: percent,
  hasCompletion: hasCompletion,
  lastActivity: '',
  lastActivityAt: activityAt,
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
  final queries = <({String companyId, String search, int offset})>[];
  int? failOffset;
  @override
  Future<EmployeePage> page(
    String companyId, {
    String search = '',
    int offset = 0,
  }) async {
    queries.add((companyId: companyId, search: search, offset: offset));
    if (offset == failOffset) throw StateError('Offline');
    final allRows = await all(companyId);
    final matching = allRows
        .where(
          (row) =>
              row.fullName.toLowerCase().contains(search.toLowerCase()) ||
              row.department.toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    return EmployeePage(
      items: matching.skip(offset).take(50).toList(),
      totalCount: allRows.length,
      filteredCount: matching.length,
    );
  }

  @override
  Future<List<Employee>> all(String companyId) async {
    calls.add(companyId);
    if (fail) throw StateError('Offline');
    if (pending != null) return pending!.future;
    return companyId == 'company-a' ? rows : [_employee(10)];
  }
}

class _CompanyData extends CompanyDataRepository {
  final _Employees employees;
  final _Reports reports;
  final List<int> participation;
  _CompanyData(
    this.employees,
    this.reports, {
    this.participation = const [0, 0, 0, 0, 0, 3],
  });

  @override
  Future<CompanyDashboard> dashboard(String companyId) async {
    final rows = await employees.all(companyId);
    final percent = await reports.completion(companyId);
    final highlights = [
      ...rows.where((row) => row.hasCompletion && row.completionPct > 0),
    ]..sort((a, b) => b.completionPct.compareTo(a.completionPct));
    return CompanyDashboard(
      employeeCount: rows.length,
      activeCourseCount: 4,
      certificateCount: 9,
      completionPct: percent,
      engagement: [
        for (var month = 5; month <= 10; month++)
          EngagementMonth(
            month: DateTime(2026, month),
            activeUsers: participation[month - 5],
          ),
      ],
      highlights: highlights.take(2).toList(),
    );
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
  Future<void> setCompanyEnabled(String courseId, bool enabled) async {}

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
  CompanyDataRepository? companyData,
}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final employeeRepo = employees ?? _Employees();
  final reportRepo = reports ?? _Reports();
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(_Session.new),
      employeeRepositoryProvider.overrideWithValue(employeeRepo),
      reportRepositoryProvider.overrideWithValue(reportRepo),
      companyDataRepositoryProvider.overrideWithValue(
        companyData ?? _CompanyData(employeeRepo, reportRepo),
      ),
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

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target, {
  double delta = 180,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 100,
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
        await tester.tap(
          find.widgetWithText(FilledButton, 'Fechar sem copiar'),
        );
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
      expect(find.text('Em breve'), findsNothing);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).data.last.value,
        1,
      );
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
      expect(find.text('Todos os funcionários (3)'), findsOneWidget);
      expect(find.textContaining('Ativos'), findsNothing);
      expect(find.text('ATIVO'), findsNothing);
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
      expect(find.text('Nenhuma atividade registrada'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'RH');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Roberto Silva'), findsOneWidget);
      expect(find.text('Pessoa 1'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Pessoa 2');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Sem dados'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final counts in [
    [0, 2, 4, 8, 1, 3],
    [0, 0, 0, 0, 0, 0],
  ]) {
    testWidgets('participation chart paints inside bounds for counts $counts', (
      tester,
    ) async {
      await _show(
        tester,
        const CompanyDashboardScreen(),
        companyData: _CompanyData(
          _Employees(),
          _Reports(),
          participation: counts,
        ),
      );
      final chart = find.byType(LineChart);
      final paint = find.descendant(
        of: chart,
        matching: find.byType(CustomPaint),
      );
      final size = tester.getSize(paint);
      final painter = tester.widget<CustomPaint>(paint).painter!;
      const margin = 40;
      final width = size.width.ceil() + 2 * margin;
      final height = size.height.ceil() + 2 * margin;

      // Padding exposes paint that escapes above the chart, rather than clipping it.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..translate(margin.toDouble(), margin.toDouble());
      painter.paint(canvas, size);
      final picture = recorder.endRecording();
      final pixels = await tester.runAsync(() async {
        final image = await picture.toImage(width, height);
        try {
          return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          image.dispose();
          picture.dispose();
        }
      });
      expect(pixels, isNotNull);
      for (var y = 0; y < margin; y++) {
        for (var x = margin; x < width - margin; x++) {
          expect(
            pixels!.getUint8((y * width + x) * 4 + 3),
            0,
            reason: 'Chart painted above its bounds at ($x, $y)',
          );
        }
      }

      final maximum = counts.fold<int>(1, (a, b) => a > b ? a : b);
      final blue = AppColors.chartBlue.toARGB32();
      for (var i = 0; i < counts.length; i++) {
        final x = (margin + 4 + (size.width - 8) * i / (counts.length - 1))
            .round();
        final y = (margin + 12 + (size.height - 34) * (1 - counts[i] / maximum))
            .round();
        final offset = (y * width + x) * 4;
        expect(
          [
            for (var channel = 0; channel < 4; channel++)
              pixels!.getUint8(offset + channel),
          ],
          [(blue >> 16) & 255, (blue >> 8) & 255, blue & 255, 255],
          reason: 'Month $i must render a dot at its normalized count',
        );
      }
      final semantics = tester.widget<Semantics>(
        find.ancestor(of: chart, matching: find.byType(Semantics)).first,
      );
      const months = ['Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out'];
      expect(
        semantics.properties.label,
        'Participação mensal: ${[for (var i = 0; i < counts.length; i++) '${months[i]}: ${counts[i]} funcionários'].join(', ')}',
      );
      expect(tester.takeException(), isNull);
    });
  }

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
    'dashboard uses full employee count and directory loads the remaining page',
    (tester) async {
      final employees = _Employees()
        ..rows = [
          for (var i = 0; i < 52; i++)
            _employee(i, percent: i == 51 ? 100 : 10),
        ];
      await _show(tester, const CompanyDashboardScreen(), employees: employees);
      expect(find.text('52'), findsOneWidget);
      await _scrollTo(tester, find.text('Destaques'));
      expect(find.text('Pessoa 51 (TI)'), findsOneWidget);
      await _show(tester, const EmployeesScreen(), employees: employees);
      expect(find.text('Exibindo 50 de 52 funcionários.'), findsOneWidget);
      await _scrollTo(tester, find.text('Carregar mais funcionários'));
      await tester.tap(find.text('Carregar mais funcionários'));
      await tester.pumpAndSettle();
      expect(employees.queries.last.offset, 50);
      await _scrollTo(tester, find.text('Pessoa 51'));
      expect(
        find.descendant(
          of: find.byType(CompanyEmployeeCard),
          matching: find.text('Pessoa 51'),
        ),
        findsOneWidget,
      );
      expect(find.text('Carregar mais funcionários'), findsNothing);
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

  testWidgets(
    'employee search finds results beyond page one and keeps exact total',
    (tester) async {
      final employees = _Employees()
        ..rows = [for (var i = 0; i < 52; i++) _employee(i)];
      await _show(tester, const EmployeesScreen(), employees: employees);
      await tester.enterText(find.byType(TextField), 'Pessoa 51');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CompanyEmployeeCard),
          matching: find.text('Pessoa 51'),
        ),
        findsOneWidget,
      );
      expect(find.text('Todos os funcionários (52)'), findsOneWidget);
      expect(
        find.text('Exibindo 1 de 1 funcionários encontrados.'),
        findsOneWidget,
      );
      expect(employees.queries.last, (
        companyId: 'company-a',
        search: 'Pessoa 51',
        offset: 0,
      ));
      expect(find.text('Carregar mais funcionários'), findsNothing);
    },
  );

  testWidgets(
    'employee cards show real activity dates and honest empty states',
    (tester) async {
      final employees = _Employees()
        ..rows = [
          _employee(0, activityAt: DateTime(2026, 10, 1, 12, 30)),
          _employee(1),
        ];
      await _show(tester, const EmployeesScreen(), employees: employees);
      expect(
        find.text('Última atividade: 01/10/2026 às 12:30'),
        findsOneWidget,
      );
      expect(find.text('Nenhuma atividade registrada'), findsOneWidget);
    },
  );

  for (final status in EmployeeStatus.values) {
    testWidgets('employee card only shows known status badges: $status', (
      tester,
    ) async {
      await _show(
        tester,
        CompanyEmployeeCard(employee: _employee(0, status: status)),
      );
      expect(
        find.text('ATIVO'),
        status == EmployeeStatus.active ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('De licença'),
        status == EmployeeStatus.onLeave ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(CompanyBadge),
        status == EmployeeStatus.unknown ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets(
    'employee page failure preserves loaded rows and retries the failed page',
    (tester) async {
      final employees = _Employees()
        ..rows = [for (var i = 0; i < 52; i++) _employee(i)]
        ..failOffset = 50;
      await _show(tester, const EmployeesScreen(), employees: employees);
      await _scrollTo(tester, find.text('Carregar mais funcionários'));
      await tester.tap(find.text('Carregar mais funcionários'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('Tentar novamente'), delta: -180);
      expect(find.text('Exibindo 50 de 52 funcionários.'), findsOneWidget);
      final callCount = employees.queries.length;
      await tester.pump(const Duration(seconds: 10));
      expect(employees.queries.length, callCount);
      employees.failOffset = null;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(employees.queries.last.offset, 50);
      await _scrollTo(tester, find.text('Pessoa 51'));
      expect(find.text('Pessoa 51'), findsOneWidget);
    },
  );

  testWidgets(
    'retained page retry stays bound to its query after search changes',
    (tester) async {
      final employees = _Employees()
        ..rows = [for (var i = 0; i < 52; i++) _employee(i)]
        ..failOffset = 50;
      final container = await _show(
        tester,
        const EmployeesScreen(),
        employees: employees,
      );
      await _scrollTo(tester, find.text('Carregar mais funcionários'));
      await tester.tap(find.text('Carregar mais funcionários'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('Tentar novamente'), delta: -180);
      final retry = tester
          .widget<CompanyErrorCard>(find.byType(CompanyErrorCard))
          .retry;
      final failedQuery = (companyId: 'company-a', search: '', offset: 50);
      final subscription = container.listen(
        companyEmployeesProvider(failedQuery),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await _scrollTo(tester, find.byType(TextField), delta: -180);
      await tester.enterText(find.byType(TextField), 'Pessoa 51');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(employees.queries.last, (
        companyId: 'company-a',
        search: 'Pessoa 51',
        offset: 0,
      ));
      expect(find.text('Tentar novamente'), findsNothing);

      employees.failOffset = null;
      retry();
      await tester.pumpAndSettle();
      expect(employees.queries.last, failedQuery);
      expect(
        find.text('Exibindo 1 de 1 funcionários encontrados.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'switching company resets employee pages and cancels pending search',
    (tester) async {
      final employees = _Employees()
        ..rows = [for (var i = 0; i < 52; i++) _employee(i)];
      final container = await _show(
        tester,
        const EmployeesScreen(),
        employees: employees,
      );
      await _scrollTo(tester, find.text('Carregar mais funcionários'));
      await tester.tap(find.text('Carregar mais funcionários'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byType(TextField), delta: -180);
      await tester.enterText(find.byType(TextField), 'Pessoa 51');
      (container.read(sessionProvider.notifier) as _Session).switchTo(_second);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      expect(employees.queries.last, (
        companyId: 'company-b',
        search: '',
        offset: 0,
      ));
      expect(find.text('Roberto Silva'), findsNothing);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '',
      );
    },
  );

  testWidgets('delayed employee response from old company is not displayed', (
    tester,
  ) async {
    final employees = _Employees();
    final container = await _show(
      tester,
      const EmployeesScreen(),
      employees: employees,
    );
    final pending = Completer<List<Employee>>();
    employees.pending = pending;
    await tester.enterText(find.byType(TextField), 'Roberto');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    employees.pending = null;
    (container.read(sessionProvider.notifier) as _Session).switchTo(_second);
    await tester.pumpAndSettle();
    pending.complete([_employee(0)]);
    await tester.pumpAndSettle();
    expect(find.text('Roberto Silva'), findsNothing);
    expect(find.text('Pessoa 10'), findsOneWidget);
  });

  testWidgets('company content toggle invalidates dashboard aggregates', (
    tester,
  ) async {
    final employees = _Employees();
    final container = await _show(
      tester,
      const CompanyContentScreen(),
      employees: employees,
    );
    final subscription = container.listen(companyDashboardProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(companyDashboardProvider.future);
    expect(employees.calls.length, 1);
    await _scrollTo(tester, find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await container.read(companyDashboardProvider.future);
    expect(employees.calls.length, 2);
    expect(tester.takeException(), isNull);
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
