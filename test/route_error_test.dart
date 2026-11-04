import 'package:educador/app/app.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/security/screens.dart';
import 'package:educador/shared/widgets/route_error_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = User(
  id: 'id',
  fullName: 'Ana',
  email: 'a@example.test',
  initials: 'A',
);
AppSession? _session;
bool _error = false;

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async {
    if (_error) throw StateError('session failed');
    return _session;
  }
}

void main() {
  setUp(() {
    _session = null;
    _error = false;
  });

  Future<ProviderContainer> start(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWith(_Session.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EducaDorApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  for (final role in Role.values) {
    testWidgets('unknown ${role.name} link recovers to authorized home', (
      tester,
    ) async {
      final access = AccessContext(
        role: role,
        companyName: 'Empresa',
        companyId: role == Role.gestor ? null : 'company-a',
      );
      _session = AppSession(user: _user, contexts: [access], active: access);
      final container = await start(tester);
      final router = container.read(routerProvider);
      router.go('/${role.name}/missing?token=secret');
      await tester.pumpAndSettle();
      expect(find.byType(RouteErrorScreen), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
      expect(find.textContaining('GoException'), findsNothing);
      await tester.tap(find.text('Voltar ao início'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/${role.name}/home',
      );
      expect(find.byType(RouteErrorScreen), findsNothing);
      router.go('/${role == Role.gestor ? 'empresa' : 'gestor'}/missing');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/${role.name}/home',
      );
    });
  }

  testWidgets('unauthenticated unknown link goes to login', (tester) async {
    final container = await start(tester);
    final router = container.read(routerProvider);
    router.go('/funcionario/missing');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.byType(RouteErrorScreen), findsNothing);
  });

  testWidgets('MFA, password, context and session errors remain gates', (
    tester,
  ) async {
    for (final mode in ['mfa', 'password', 'context', 'error']) {
      _error = mode == 'error';
      _session = AppSession(
        user: _user,
        contexts: const [],
        needsMfa: mode == 'mfa',
        needsPassword: mode == 'password',
      );
      final container = await start(tester);
      final router = container.read(routerProvider);
      router.go('/gestor/missing');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        {
          'mfa': '/mfa',
          'password': '/set-password',
          'context': '/contexts',
          'error': '/session-error',
        }[mode],
      );
      expect(find.byType(RouteErrorScreen), findsNothing);
      if (mode == 'mfa') {
        expect(find.byType(MfaChallengeScreen), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('mobile recovery is keyboard accessible', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const access = AccessContext(role: Role.gestor, companyName: 'Plataforma');
    _session = const AppSession(
      user: _user,
      contexts: [access],
      active: access,
    );
    final container = await start(tester);
    final router = container.read(routerProvider);
    router.go('/gestor/missing');
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Voltar ao início');
    expect(button, findsOneWidget);
    tester.widget<FilledButton>(button).focusNode?.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/gestor/home');
    expect(tester.takeException(), isNull);
  });
}
