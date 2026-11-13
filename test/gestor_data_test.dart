import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';

import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/gestor_providers.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/gestor/screens.dart';
import 'package:educador/features/gestor/widgets.dart';
import 'package:educador/features/content/catalog_screen.dart';
import 'package:educador/features/content/publish_video_screen.dart';
import 'package:educador/shared/widgets/charts.dart';
import 'package:educador/shared/widgets/common.dart';
import 'package:educador/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _gestor = AccessContext(role: Role.gestor, companyName: 'Plataforma');
const _empresa = AccessContext(
  role: Role.empresa,
  companyId: 'company',
  companyName: 'Empresa',
);
const _user = User(
  id: 'person',
  fullName: 'Ana Silva',
  email: 'ana@example.test',
  initials: 'AS',
);

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async => const AppSession(
    user: _user,
    contexts: [_gestor, _empresa],
    active: _gestor,
  );

  void changeUser(String id) {
    state = AsyncData(
      AppSession(
        user: User(
          id: id,
          fullName: 'Outra',
          email: 'other@example.test',
          initials: 'O',
        ),
        contexts: const [_gestor, _empresa],
        active: _gestor,
      ),
    );
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
  }
}

class _Invites extends InvitationRepository {
  @override
  Future<List<PendingInvitation>> pending({
    String search = '',
    int offset = 0,
    Role? role,
    String? companyId,
  }) async => [];
}

class _Dashboard extends GestorRepository {
  int calls = 0;
  bool fail = false;
  Completer<GestorDashboard>? delayed;

  @override
  Future<GestorDashboard> dashboard() async {
    calls++;
    if (fail) throw StateError('Offline');
    if (delayed != null) return delayed!.future;
    return GestorDashboard(
      companyCount: 2,
      newCompanyCount: 1,
      userCount: 1234,
      activeUserCount: 5,
      completionPct: 37.5,
      growth: [
        for (var month = 5; month <= 10; month++)
          GrowthMonth(
            month: DateTime(2026, month),
            companies: month,
            users: month * 10,
          ),
      ],
      activities: [
        PlatformActivity(
          id: 'a',
          kind: 'company',
          name: 'Empresa real',
          occurredAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ],
    );
  }
}

Company _company(
  int index, {
  bool active = true,
  String? name,
  String? cnpj,
  String? responsible,
}) => Company(
  id: 'company-$index',
  name: name ?? 'Empresa $index',
  cnpj: cnpj ?? '00.000.000/0001-00',
  responsibleName: responsible ?? 'Responsável',
  email: '',
  phone: '',
  address: '',
  city: '',
  state: '',
  field: '',
  employeeCount: 7,
  active: active,
  registeredAt: '2026-09-01',
  initials: 'E',
);

class _Companies extends CompanyRepository {
  final List<CompanyQuery> calls = [];
  bool fail = false;
  bool empty = false;
  List<Company>? itemsOverride;
  @override
  Future<CompanyPage> page({
    String search = '',
    bool? active,
    int offset = 0,
  }) async {
    calls.add((search: search, active: active, offset: offset));
    if (fail) throw StateError('Offline');
    final items =
        itemsOverride ??
        (empty
            ? <Company>[]
            : search.isNotEmpty || active != null
            ? [_company(999, active: active ?? true)]
            : offset == 0
            ? [for (var i = 0; i < 50; i++) _company(i)]
            : [_company(50)]);
    return CompanyPage(items: items, activeCount: 50, inactiveCount: 1);
  }
}

class _CsvPicker extends FilePicker {
  final files = <Uint8List>[];
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    files.add(bytes!);
    return null;
  }
}

class _Reports extends ReportRepository {
  int completionCalls = 0;
  final List<ReportPeriod> activityCalls = [];
  bool fail = false;
  bool empty = false;
  Completer<ExportPage<CompanyCompletion>>? exportPending;
  Completer<PlatformActivityReport>? activityPending;
  List<CompanyCompletion>? completionOverride;
  List<CompanyCompletion>? exportOverride;
  final exportAfters = <String?>[];
  int exportCalls = 0;
  @override
  Future<List<CompanyCompletion>> platformCompletion({int offset = 0}) async {
    completionCalls++;
    if (completionOverride != null) return completionOverride!;
    if (fail) throw StateError('Offline');
    return empty
        ? []
        : const [
            CompanyCompletion(
              companyId: 'a',
              company: 'Empresa real',
              percent: 37.5,
            ),
            CompanyCompletion(companyId: 'b', company: 'Sem funcionários'),
          ];
  }

  @override
  Future<ExportPage<CompanyCompletion>> platformCompletionExport({
    String? after,
  }) async {
    exportCalls++;
    exportAfters.add(after);
    if (exportPending != null) return exportPending!.future;
    if (fail) throw StateError('Offline');
    final rows =
        exportOverride ??
        completionOverride ??
        (empty
            ? const <CompanyCompletion>[]
            : const [
                CompanyCompletion(
                  companyId: 'a',
                  company: 'Empresa real',
                  percent: 37.5,
                ),
                CompanyCompletion(companyId: 'b', company: 'Sem funcionários'),
              ]);
    final start = after == null
        ? 0
        : rows.indexWhere((row) => row.companyId == after) + 1;
    final end = (start + 50).clamp(0, rows.length);
    return ExportPage(total: rows.length, items: rows.sublist(start, end));
  }

  @override
  Future<PlatformActivityReport> platformActivity({
    required DateTime from,
    required DateTime to,
  }) async {
    activityCalls.add((from: from, to: to));
    if (activityPending != null) return activityPending!.future;
    if (fail) throw StateError('Offline');
    return PlatformActivityReport(
      engagement: [EngagementMonth(month: from, activeUsers: empty ? 0 : 2)],
      popularContent: empty
          ? []
          : const [
              PopularContent(
                courseId: 'course',
                title: 'Curso real',
                kind: 'course',
                completions: 3,
              ),
            ],
    );
  }
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  Widget screen, {
  _Dashboard? dashboard,
  _Companies? companies,
  _Reports? reports,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        invitationRepositoryProvider.overrideWithValue(_Invites()),
        if (dashboard != null)
          gestorRepositoryProvider.overrideWithValue(dashboard),
        if (companies != null)
          companyRepositoryProvider.overrideWithValue(companies),
        if (reports != null)
          reportRepositoryProvider.overrideWithValue(reports),
      ],
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(screen.runtimeType)),
  );
}

Future<(ProviderContainer, GoRouter)> _reportShell(
  WidgetTester tester,
  _Reports reports,
) async {
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(_Session.new),
      reportRepositoryProvider.overrideWithValue(reports),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.future);
  final router = GoRouter(
    initialLocation: '/gestor/relatorios',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => Scaffold(body: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/gestor/relatorios',
                builder: (_, _) => const GestorReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/gestor/home',
                builder: (_, _) => const Text('Outra aba'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  testWidgets('dashboard uses real repository and session instead of mocks', (
    tester,
  ) async {
    await _show(tester, const GestorDashboardScreen(), dashboard: _Dashboard());
    expect(find.text('Olá, Ana'), findsOneWidget);
    expect(find.text('AS'), findsOneWidget);
    expect(find.text('1.234'), findsOneWidget);
    expect(find.text('37,5%'), findsOneWidget);
    expect(find.text('47'), findsNothing);
    expect(
      tester.widget<LineChart>(find.byType(LineChart)).secondaryData,
      hasLength(6),
    );
    await tester.scrollUntilVisible(find.text('Empresa real cadastrada'), 200);
    expect(find.text('Há 5 min'), findsOneWidget);
  });

  testWidgets('dashboard preserves skeleton and retries errors', (
    tester,
  ) async {
    final repo = _Dashboard()..fail = true;
    await _show(tester, const GestorDashboardScreen(), dashboard: repo);
    expect(find.text('Não foi possível carregar o painel.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(repo.calls, 1);
    repo
      ..fail = false
      ..delayed = Completer<GestorDashboard>();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(find.byType(DataSkeleton), findsWidgets);
    repo.delayed!.complete(await _Dashboard().dashboard());
    await tester.pumpAndSettle();
    expect(find.text('1.234'), findsOneWidget);
    expect(repo.calls, 2);
  });

  testWidgets('dashboard bell opens notification settings', (tester) async {
    await _show(tester, const GestorDashboardScreen(), dashboard: _Dashboard());
    await tester.tap(find.byTooltip('Notificações'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull to refresh reloads dashboard', (tester) async {
    final repo = _Dashboard();
    await _show(tester, const GestorDashboardScreen(), dashboard: repo);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(repo.calls, 2);
  });

  testWidgets('companies search, status and pagination query the server', (
    tester,
  ) async {
    final repo = _Companies();
    await _show(tester, const CompaniesScreen(), companies: repo);
    expect(find.text('Ativas (50)'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Carregar mais empresas'),
      1500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Carregar mais empresas'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.offset, 50);
    await tester.scrollUntilVisible(
      find.text('Empresa 50'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Empresa 50'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Pesquise o nome da empresa',
      ),
      -1000,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Pesquise o nome da empresa',
      ),
      ' %_ ',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.calls.last.search, '%_');
    expect(repo.calls.last.offset, 0);
    await tester.tap(find.text('Inativas (1)'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.active, isFalse);
    expect(find.text('Inativa'), findsOneWidget);
  });

  testWidgets(
    'company cards omit empty metadata and retain long values on mobile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const longName =
          'Empresa com nome extremamente longo para testar a apresentação em uma tela pequena';
      const longResponsible =
          'Pessoa responsável com nome extremamente longo para verificar a apresentação';
      final repo = _Companies()
        ..itemsOverride = [
          _company(1, cnpj: '', responsible: ''),
          _company(2, cnpj: '   ', responsible: '\t '),
          _company(
            3,
            name: longName,
            cnpj: '12.345.678/0001-90',
            responsible: longResponsible,
          ),
        ];
      await _show(tester, const CompaniesScreen(), companies: repo);
      for (final name in ['Empresa 1', 'Empresa 2']) {
        final card = find.ancestor(
          of: find.text(name),
          matching: find.byType(AppCard),
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('CNPJ:')),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.text('Pessoa responsável')),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.text('Funcionários')),
          findsOneWidget,
        );
      }
      await tester.scrollUntilVisible(
        find.text(longName),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CNPJ: 12.345.678/0001-90'), findsOneWidget);
      expect(find.text(longResponsible), findsOneWidget);
      expect(tester.getSize(find.text(longName)).height, greaterThan(20));
      expect(
        tester.getSize(find.text(longResponsible)).height,
        greaterThan(20),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('companies show no-data and retry failed requests', (
    tester,
  ) async {
    final repo = _Companies()..fail = true;
    await _show(tester, const CompaniesScreen(), companies: repo);
    expect(find.text('Não foi possível carregar empresas.'), findsOneWidget);
    repo
      ..fail = false
      ..empty = true;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma empresa cadastrada.'), findsOneWidget);
  });

  testWidgets(
    'companies match prototype styling and keep invitation controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _show(tester, const CompaniesScreen(), companies: _Companies());

      final title = find.text('Empresas Registradas');
      expect(tester.getTopLeft(title).dx, 32);
      final titleStyle = DefaultTextStyle.of(tester.element(title)).style;
      expect(titleStyle.fontFamily, AppFonts.outfit);
      expect(titleStyle.fontWeight, FontWeight.w700);
      expect(
        tester
            .getSize(
              find.byWidgetPredicate(
                (w) =>
                    w is TextField &&
                    w.decoration?.hintText == 'Pesquise o nome da empresa',
              ),
            )
            .height,
        36,
      );
      expect(tester.getSize(find.byType(FilterChips)).height, 28);
      final search = tester.widget<SvgIcon>(
        find
            .byWidgetPredicate(
              (widget) => widget is SvgIcon && widget.asset == AppIcons.search,
            )
            .first,
      );
      expect(search.size, 18);
      expect(search.color, const Color(0xFF475569));

      final nameStyle = tester.widget<Text>(find.text('Empresa 0')).style!;
      expect(nameStyle.fontFamily, AppFonts.outfit);
      expect(nameStyle.fontWeight, FontWeight.w700);
      final card = find.ancestor(
        of: find.text('Empresa 0'),
        matching: find.byType(AppCard),
      );
      expect(
        find.descendant(of: card, matching: find.byType(Divider)),
        findsOneWidget,
      );
      expect(find.text('Convites pendentes'), findsOneWidget);
      expect(find.text('Nenhum convite pendente.'), findsOneWidget);
      expect(find.text('Convidar gestor da empresa'), findsWidgets);
      final addButton = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(addButton.backgroundColor, isNull);
      expect(addButton.shape, isNull);
      final addTheme = Theme.of(
        tester.element(find.byType(FloatingActionButton)),
      ).floatingActionButtonTheme;
      expect(addTheme.backgroundColor, AppColors.primary);
      expect(addTheme.shape, isA<CircleBorder>());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'period picker is disabled while export is pending and saved bytes use captured period',
    (tester) async {
      final repo = _Reports();
      await _show(tester, const GestorReportsScreen(), reports: repo);
      final picker = _CsvPicker();
      FilePicker.platform = picker;
      repo.exportPending = Completer<ExportPage<CompanyCompletion>>();
      await tester.tap(find.byTooltip('Exportar CSV'));
      await tester.pump();
      await tester.tap(find.byType(AppCard).first);
      await tester.pump();
      expect(find.byType(DateRangePickerDialog), findsNothing);
      final period = repo.activityCalls.first;
      repo.exportPending!.complete(
        const ExportPage(
          total: 1,
          items: [
            CompanyCompletion(
              companyId: 'a',
              company: 'Empresa; "A"',
              percent: 37.5,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.exportAfters, [null, null]);
      expect(repo.activityCalls.last, period);
      expect(picker.files, hasLength(1));
      final csv = utf8.decode(picker.files.single.skip(3).toList());
      expect(csv, contains('"Empresa; ""A""";"37,5"'));
      expect(
        csv,
        contains(
          '"${formatDate(period.from)}";"${formatDate(period.to)}";"Curso real";"3"',
        ),
      );
    },
  );

  for (final duringActivity in [false, true]) {
    testWidgets(
      'leaving retained gestor tab cancels pending ${duringActivity ? 'activity' : 'completion'} RPC',
      (tester) async {
        final repo = _Reports();
        final (_, router) = await _reportShell(tester, repo);
        final picker = _CsvPicker();
        FilePicker.platform = picker;
        if (duringActivity) {
          repo.activityPending = Completer<PlatformActivityReport>();
        } else {
          repo.exportPending = Completer<ExportPage<CompanyCompletion>>();
        }
        await tester.tap(find.byTooltip('Exportar CSV'));
        await tester.pump();
        expect(repo.exportCalls, duringActivity ? 2 : 1);
        router.go('/gestor/home');
        await tester.pumpAndSettle();
        router.go('/gestor/relatorios');
        await tester.pump();
        if (duringActivity) {
          repo.activityPending!.complete(
            PlatformActivityReport(engagement: [], popularContent: []),
          );
        } else {
          repo.exportPending!.complete(const ExportPage(total: 0, items: []));
        }
        await tester.pumpAndSettle();
        expect(picker.files, isEmpty);
        expect(repo.activityCalls.length, duringActivity ? 2 : 1);
      },
    );
  }

  for (final identity in [false, true]) {
    testWidgets(
      'pending gestor export cancels on ${identity ? 'account' : 'context'} change',
      (tester) async {
        final repo = _Reports();
        final (container, _) = await _reportShell(tester, repo);
        final picker = _CsvPicker();
        FilePicker.platform = picker;
        repo.exportPending = Completer<ExportPage<CompanyCompletion>>();
        await tester.tap(find.byTooltip('Exportar CSV'));
        await tester.pump();
        final session = container.read(sessionProvider.notifier) as _Session;
        if (identity) {
          session.changeUser('different');
        } else {
          await session.select(_empresa);
        }
        await tester.pump();
        final callsAfterChange = repo.activityCalls.length;
        repo.exportPending!.complete(const ExportPage(total: 0, items: []));
        await tester.pumpAndSettle();
        expect(picker.files, isEmpty);
        expect(repo.activityCalls, hasLength(callsAfterChange));
      },
    );
  }

  for (final count in [0, 49, 50, 51, 101]) {
    testWidgets('gestor CSV exports $count companies across pages', (
      tester,
    ) async {
      final repo = _Reports();
      await _show(tester, const GestorReportsScreen(), reports: repo);
      final picker = _CsvPicker();
      FilePicker.platform = picker;
      repo.exportOverride = List.generate(
        count,
        (i) => CompanyCompletion(
          companyId: '$i'.padLeft(4, '0'),
          company: 'Empresa $i',
          percent: 10,
        ),
      );
      await tester.tap(find.byTooltip('Exportar CSV'));
      await tester.pumpAndSettle();
      expect(picker.files, hasLength(1));
      final csv = utf8.decode(picker.files.single.skip(3).toList());
      if (count == 0) {
        expect(csv, isNot(contains('"Empresa 0"')));
      } else {
        expect(csv, contains('"Empresa 0"'));
        expect(csv, contains('"Empresa ${count - 1}"'));
      }
      if (count > 100) {
        expect(repo.exportAfters.take(3), [null, '0049', '0099']);
      } else if (count > 50) {
        expect(repo.exportAfters.take(2), [null, '0049']);
      }
    });
  }

  testWidgets('gestor CSV rejects more than 1.000 companies', (tester) async {
    final repo = _Reports();
    await _show(tester, const GestorReportsScreen(), reports: repo);
    final picker = _CsvPicker();
    FilePicker.platform = picker;
    repo.exportOverride = List.generate(
      1001,
      (i) => CompanyCompletion(
        companyId: '$i',
        company: 'Empresa $i',
        percent: 10,
      ),
    );
    await tester.tap(find.byTooltip('Exportar CSV'));
    await tester.pumpAndSettle();
    expect(picker.files, isEmpty);
    expect(
      find.text(
        'Exportação limitada a 1.000 empresas. Refine os dados e tente novamente.',
      ),
      findsOneWidget,
    );
    expect(repo.exportAfters, [null]);
  });

  testWidgets(
    'reports load current completion independently of the date selector',
    (tester) async {
      final repo = _Reports();
      await _show(tester, const GestorReportsScreen(), reports: repo);
      final heading = find.text('Conclusão pela Empresa');
      expect(
        find.ancestor(of: heading, matching: find.byType(AppCard)),
        findsOneWidget,
      );
      final completionBar = tester.widget<ReportBarRow>(
        find.byType(ReportBarRow).first,
      );
      expect(completionBar.compact, isTrue);
      expect(completionBar.color, AppColors.primary);
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('Sem dados'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Curso real'), 200);
      expect(find.text('3 conclusões'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppCard).first);
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      final localizations = MaterialLocalizations.of(
        tester.element(find.byType(DateRangePickerDialog)),
      );
      await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final from = DateTime(now.year, now.month - 1, 1);
      final to = DateTime(now.year, now.month, 0);
      String input(DateTime date) =>
          '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/${date.year}';
      await tester.enterText(find.byType(TextField).at(0), input(from));
      await tester.enterText(find.byType(TextField).at(1), input(to));
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(repo.activityCalls.last, (from: from, to: to));
      expect(repo.completionCalls, 1);
      expect(repo.activityCalls, hasLength(2));
    },
  );

  testWidgets('reports show honest empty states and enable CSV', (
    tester,
  ) async {
    await _show(
      tester,
      const GestorReportsScreen(),
      reports: _Reports()..empty = true,
    );
    final export = tester.widget<IconButton>(find.byType(IconButton).first);
    expect(export.onPressed, isNotNull);
    expect(export.tooltip, 'Exportar CSV');
    expect(find.text('Nenhuma empresa cadastrada.'), findsOneWidget);
    expect(find.text('Nenhuma conclusão no período.'), findsOneWidget);
    final popularEmpty = find.text('Nenhuma conclusão no período.');
    expect(tester.widget<Text>(popularEmpty).style!.fontSize, 12);
    expect(tester.widget<Text>(popularEmpty).textAlign, TextAlign.center);
    await tester.scrollUntilVisible(
      find.text('Nenhuma atividade no período.'),
      200,
    );
    expect(find.text('Nenhuma atividade no período.'), findsOneWidget);
    final emptyState = find.text('Nenhuma atividade no período.');
    final card = find.ancestor(of: emptyState, matching: find.byType(AppCard));
    expect(tester.widget<Text>(emptyState).textAlign, TextAlign.center);
    expect(tester.widget<Text>(emptyState).style!.fontSize, 12);
    expect(
      tester.getCenter(emptyState).dx,
      closeTo(tester.getCenter(card).dx, 0.1),
    );
  });

  testWidgets('reports retry query failures', (tester) async {
    final repo = _Reports()..fail = true;
    await _show(tester, const GestorReportsScreen(), reports: repo);
    expect(find.text('Não foi possível carregar a conclusão.'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('Tentar novamente').first);
    await tester.pumpAndSettle();
    expect(find.text('38%'), findsOneWidget);
  });

  testWidgets(
    'context changes discard platform data and stop platform requests',
    (tester) async {
      final repo = _Dashboard();
      final container = await _show(
        tester,
        const GestorDashboardScreen(),
        dashboard: repo,
      );
      await container.read(sessionProvider.notifier).select(_empresa);
      await tester.pumpAndSettle();
      expect(find.text('1.234'), findsNothing);
      expect(repo.calls, 1);
      await container.read(sessionProvider.notifier).select(_gestor);
      await tester.pumpAndSettle();
      expect(find.text('1.234'), findsOneWidget);
      expect(repo.calls, 2);
    },
  );

  testWidgets('Gestor content routes no longer select mock implementations', (
    tester,
  ) async {
    await _show(tester, const ContentManagementScreen());
    expect(find.byType(ContentCatalogScreen), findsOneWidget);
    await _show(tester, const AddTrailScreen());
    expect(find.byType(PublishVideoScreen), findsOneWidget);
    expect(find.text('Criar curso'), findsOneWidget);
  });

  for (final width in [320.0, 1000.0]) {
    testWidgets('Gestor screens fit width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _show(
        tester,
        const GestorDashboardScreen(),
        dashboard: _Dashboard(),
      );
      expect(tester.takeException(), isNull);
      await _show(tester, const CompaniesScreen(), companies: _Companies());
      expect(tester.takeException(), isNull);
      await _show(tester, const GestorReportsScreen(), reports: _Reports());
      await tester.scrollUntilVisible(find.byType(BarChart), 200);
      expect(tester.takeException(), isNull);
    });
  }
}
