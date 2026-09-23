import 'dart:async';

import 'package:educador/app/app.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/company/screens.dart';
import 'package:educador/features/auth/screens.dart';
import 'package:educador/features/auth/onboarding_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _manager = AccessContext(
  role: Role.empresa,
  companyId: 'company-a',
  companyName: 'Empresa A',
);
const _employee = AccessContext(
  role: Role.funcionario,
  companyId: 'company-a',
  companyName: 'Empresa A',
);
const _user = User(
  id: 'person',
  fullName: 'Ana Silva',
  email: 'ana@example.test',
  initials: 'AS',
);

class _TestSession extends SessionController {
  @override
  Future<AppSession?> build() async =>
      const AppSession(user: _user, contexts: [_manager, _employee]);

  @override
  Future<void> select(AccessContext context) async {
    state = AsyncData(
      AppSession(
        user: _user,
        contexts: const [_manager, _employee],
        active: context,
      ),
    );
    sessionRefresh.refresh();
  }
}

final _loaded = Completer<AppSession?>();

class _SlowSession extends SessionController {
  @override
  Future<AppSession?> build() => _loaded.future;
}

void main() {
  testWidgets('selecting manager cannot open the employee area', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWith(_TestSession.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EducaDorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Escolher perfil'), findsOneWidget);
    expect(find.text(_manager.label), findsOneWidget);
    expect(find.text(_employee.label), findsOneWidget);

    await tester.tap(find.text(_manager.label));
    await tester.pumpAndSettle();
    expect(find.byType(CompanyDashboardScreen), findsOneWidget);

    container.read(routerProvider).go('/funcionario/home');
    await tester.pumpAndSettle();
    expect(find.byType(CompanyDashboardScreen), findsOneWidget);

    final invite = Uri(
      path: '/invite/accept',
      queryParameters: {'token': 'a' * 64},
    ).toString();
    container
        .read(routerProvider)
        .go(
          Uri(path: '/login', queryParameters: {'redirect': invite}).toString(),
        );
    await tester.pumpAndSettle();
    expect(find.byType(AcceptInviteScreen), findsOneWidget);
  });

  testWidgets('splash continues when session restoration takes longer', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWith(_SlowSession.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EducaDorApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SplashScreen), findsOneWidget);

    _loaded.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
