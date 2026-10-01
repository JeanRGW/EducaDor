import 'dart:async';

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

Company _company(int index, {bool active = true}) => Company(
  id: 'company-$index',
  name: 'Empresa $index',
  cnpj: '00.000.000/0001-00',
  responsibleName: 'Responsável',
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
  @override
  Future<CompanyPage> page({
    String search = '',
    bool? active,
    int offset = 0,
  }) async {
    calls.add((search: search, active: active, offset: offset));
    if (fail) throw StateError('Offline');
    final items = empty
        ? <Company>[]
        : search.isNotEmpty || active != null
        ? [_company(999, active: active ?? true)]
        : offset == 0
        ? [for (var i = 0; i < 50; i++) _company(i)]
        : [_company(50)];
    return CompanyPage(items: items, activeCount: 50, inactiveCount: 1);
  }
}

class _Reports extends ReportRepository {
  int completionCalls = 0;
  final List<ReportPeriod> activityCalls = [];
  bool fail = false;
  bool empty = false;
  @override
  Future<List<CompanyCompletion>> platformCompletion({int offset = 0}) async {
    completionCalls++;
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
  Future<PlatformActivityReport> platformActivity({
    required DateTime from,
    required DateTime to,
  }) async {
    activityCalls.add((from: from, to: to));
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
    await tester.drag(find.byType(ListView).first, const Offset(0, 15000));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' %_ ');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.calls.last.search, '%_');
    expect(repo.calls.last.offset, 0);
    await tester.tap(find.text('Inativas (1)'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.active, isFalse);
    expect(find.text('Inativa'), findsOneWidget);
  });

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
    'reports load current completion independently of the date selector',
    (tester) async {
      final repo = _Reports();
      await _show(tester, const GestorReportsScreen(), reports: repo);
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

  testWidgets('reports show honest empty states and disable deferred CSV', (
    tester,
  ) async {
    await _show(
      tester,
      const GestorReportsScreen(),
      reports: _Reports()..empty = true,
    );
    final export = tester.widget<IconButton>(find.byType(IconButton).first);
    expect(export.onPressed, isNull);
    expect(find.text('Nenhuma empresa cadastrada.'), findsOneWidget);
    expect(find.text('Nenhuma conclusão no período.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Nenhuma atividade no período.'),
      200,
    );
    expect(find.text('Nenhuma atividade no período.'), findsOneWidget);
    final emptyState = find.text('Nenhuma atividade no período.');
    final card = find.ancestor(of: emptyState, matching: find.byType(AppCard));
    expect(tester.widget<Text>(emptyState).textAlign, TextAlign.center);
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
    expect(find.text('Vídeo do YouTube'), findsOneWidget);
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
      await _show(
        tester,
        const CompaniesScreen(),
        companies: _Companies()..empty = true,
      );
      expect(tester.takeException(), isNull);
      await _show(tester, const GestorReportsScreen(), reports: _Reports());
      await tester.scrollUntilVisible(find.byType(BarChart), 200);
      expect(tester.takeException(), isNull);
    });
  }
}
