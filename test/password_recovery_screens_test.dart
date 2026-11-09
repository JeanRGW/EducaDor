import 'dart:async';

import 'package:educador/app/app.dart';
import 'package:educador/app/theme.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/repositories/notification_controller.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/auth/recovery_screens.dart';
import 'package:educador/features/security/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _user = User(
  id: 'user',
  fullName: 'Ana',
  email: 'a@example.test',
  initials: 'A',
);
const _recovery = AppSession(
  user: _user,
  contexts: [],
  recoveringPassword: true,
);

class _Auth extends AuthRepository {
  final requests = <String>[];
  int verifications = 0;
  int updates = 0;
  int completions = 0;
  bool rejectLink = false;
  bool failCompletion = false;
  Completer<void>? pending;
  @override
  Future<void> requestPasswordReset(String email) async {
    requests.add(email.trim());
    await pending?.future;
  }

  @override
  Future<void> verifyRecoveryToken(String tokenHash) async {
    verifications++;
    if (rejectLink) throw StateError('expired');
  }

  @override
  Future<void> updateRecoveredPassword(String password) async {
    updates++;
  }

  @override
  Future<void> completeRecoveredPassword() async {
    completions++;
    if (failCompletion) throw StateError('offline');
  }
}

class _Session extends SessionController {
  _Session([this.initial = _recovery]);
  final AppSession? initial;
  bool failReload = false;
  bool failLogout = false;
  int logouts = 0;
  @override
  Future<AppSession?> build() async => initial;
  @override
  Future<AppSession?> reload() async {
    if (failReload) throw StateError('offline');
    state = const AsyncData(_recovery);
    sessionRefresh.refresh();
    return _recovery;
  }

  @override
  Future<void> logout() async {
    logouts++;
    if (failLogout) throw StateError('offline');
    state = const AsyncData(null);
    sessionRefresh.refresh();
  }

  void setSession(AppSession value) {
    state = AsyncData(value);
    sessionRefresh.refresh();
  }
}

Future<GoRouter> _show(
  WidgetTester tester,
  Widget page,
  _Auth auth,
  _Session session,
) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      sessionProvider.overrideWith(() => session),
    ],
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => page),
      GoRoute(
        path: '/recover',
        builder: (_, _) => const RecoverPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('Login destination')),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  for (final address in ['known@example.test', 'unknown@example.test']) {
    testWidgets(
      'request confirmation is generic for $address and resend is throttled',
      (tester) async {
        final auth = _Auth();
        await _show(
          tester,
          const RecoverPasswordScreen(),
          auth,
          _Session(null),
        );
        await tester.enterText(find.byType(TextField), address);
        await tester.tap(find.text('Enviar link de recuperação'));
        await tester.pumpAndSettle();
        expect(auth.requests, [address]);
        expect(find.text(recoveryConfirmation), findsOneWidget);
        expect(find.text(address), findsNothing);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Reenviar em 60s'),
              )
              .onPressed,
          isNull,
        );
        await tester.pump(const Duration(seconds: 60));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reenviar link'));
        await tester.pumpAndSettle();
        expect(auth.requests.length, 2);
      },
    );
  }

  testWidgets('invalid email is rejected and pending send cannot be replayed', (
    tester,
  ) async {
    final auth = _Auth()..pending = Completer<void>();
    await _show(tester, const RecoverPasswordScreen(), auth, _Session(null));
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.tap(find.text('Enviar link de recuperação'));
    await tester.pump();
    expect(auth.requests, isEmpty);
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a@example.test');
    await tester.tap(find.text('Enviar link de recuperação'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enviando...'),
          )
          .onPressed,
      isNull,
    );
    auth.pending!.complete();
    await tester.pumpAndSettle();
    expect(auth.requests.length, 1);
  });

  testWidgets(
    'receiver does not auto-consume tokens and refresh retry does not replay a verified link',
    (tester) async {
      final auth = _Auth();
      final session = _Session()..failReload = true;
      final hash = 'a' * 64;
      final router = await _show(
        tester,
        RecoveryLinkScreen(tokenHash: hash),
        auth,
        session,
      );
      expect(auth.verifications, 0);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(auth.verifications, 1);
      expect(find.textContaining('Link confirmado.'), findsOneWidget);
      expect(find.textContaining(hash), findsNothing);
      session.failReload = false;
      await tester.tap(find.text('Continuar recuperação'));
      await tester.pumpAndSettle();
      expect(auth.verifications, 1);
      expect(router.routeInformationProvider.value.uri.path, '/reset-password');
      expect(router.routeInformationProvider.value.uri.fragment, isEmpty);
    },
  );

  testWidgets(
    'expired or consumed link offers a new request without changing password',
    (tester) async {
      final auth = _Auth()..rejectLink = true;
      await _show(
        tester,
        RecoveryLinkScreen(tokenHash: 'a' * 64),
        auth,
        _Session(null),
      );
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('já foi utilizado'), findsOneWidget);
      expect(auth.updates, 0);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'password completion retry never repeats a successful Auth password change',
    (tester) async {
      final auth = _Auth()..failCompletion = true;
      final session = _Session();
      await _show(tester, const ResetPasswordScreen(), auth, session);
      await tester.enterText(find.byType(TextField).at(0), 'new-password');
      await tester.enterText(find.byType(TextField).at(1), 'different');
      await tester.tap(find.text('Salvar nova senha'));
      await tester.pump();
      expect(auth.updates, 0);
      await tester.enterText(find.byType(TextField).at(1), 'new-password');
      await tester.tap(find.text('Salvar nova senha'));
      await tester.pumpAndSettle();
      expect(auth.updates, 1);
      expect(auth.completions, 1);
      expect(find.byType(TextField), findsNothing);
      auth.failCompletion = false;
      await tester.tap(find.text('Finalizar recuperação'));
      await tester.pumpAndSettle();
      expect(auth.updates, 1);
      expect(auth.completions, 2);
      expect(session.logouts, 1);
      expect(find.text('Senha atualizada'), findsOneWidget);
    },
  );

  testWidgets('logout retry does not replay password or completion writes', (
    tester,
  ) async {
    final auth = _Auth();
    final session = _Session()..failLogout = true;
    await _show(tester, const ResetPasswordScreen(), auth, session);
    await tester.enterText(find.byType(TextField).at(0), 'new-password');
    await tester.enterText(find.byType(TextField).at(1), 'new-password');
    await tester.tap(find.text('Salvar nova senha'));
    await tester.pumpAndSettle();
    session.failLogout = false;
    await tester.tap(find.text('Finalizar recuperação'));
    await tester.pumpAndSettle();
    expect(auth.updates, 1);
    expect(auth.completions, 1);
    expect(session.logouts, 2);
    expect(find.text('Senha atualizada'), findsOneWidget);
  });

  testWidgets('MFA gate resumes recovery rather than going to role selection', (
    tester,
  ) async {
    final session = _Session(
      const AppSession(
        user: _user,
        contexts: [],
        needsMfa: true,
        recoveringPassword: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => session),
        authRepositoryProvider.overrideWithValue(_Auth()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EducaDorApp(),
      ),
    );
    await tester.pumpAndSettle();
    final router = container.read(routerProvider);
    router.go('/reset-password');
    await tester.pumpAndSettle();
    expect(find.byType(MfaChallengeScreen), findsOneWidget);
    session.setSession(_recovery);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/reset-password');
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(notificationContextKey(_recovery), isNull);
    router.go('/gestor/home');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/reset-password');
  });

  testWidgets('request form fits a narrow screen with an inset header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _show(tester, const RecoverPasswordScreen(), _Auth(), _Session(null));
    expect(find.byType(TextField), findsOneWidget);
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Recuperar senha'),
    );
    expect(tester.getTopLeft(title).dx, 20);
    expect(tester.getRect(title).right, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('callback and new-password headers share the same inset', (
    tester,
  ) async {
    for (final page in [
      const RecoveryLinkScreen(tokenHash: null),
      const ResetPasswordScreen(),
    ]) {
      await _show(tester, page, _Auth(), _Session());
      final title = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Recuperar senha'),
      );
      expect(tester.getTopLeft(title).dx, 20);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
