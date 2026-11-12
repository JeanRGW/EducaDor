import 'package:educador/app/theme.dart';
import 'package:educador/core/pending_invite.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/auth/onboarding_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _session = AppSession(
  user: User(
    id: 'user',
    fullName: 'Ana',
    email: 'ana@example.test',
    initials: 'A',
  ),
  contexts: [AccessContext(role: Role.gestor, companyName: 'Plataforma')],
  active: AccessContext(role: Role.gestor, companyName: 'Plataforma'),
);

class _Auth extends AuthRepository {
  int updates = 0;
  int reloads = 0;
  bool failReload = false;
  bool failUpdate = false;
  bool needsPassword = false;

  @override
  Future<AppSession?> current() async {
    reloads++;
    if (failReload) throw StateError('Offline');
    return AppSession(
      user: _session.user,
      contexts: _session.contexts,
      active: _session.active,
      needsPassword: needsPassword,
    );
  }

  @override
  Future<void> updatePassword(String password) async {
    updates++;
    if (failUpdate) throw StateError('Completion not confirmed');
  }
}

class _Invites extends InvitationRepository {
  int accepts = 0;
  bool invalid = false;
  String? token;

  @override
  Future<void> accept(String token) async {
    accepts++;
    this.token = token;
    if (invalid) throw StateError('Invalid invitation');
  }
}

Future<GoRouter> _show(
  WidgetTester tester,
  _Auth auth,
  _Invites invites, {
  bool password = false,
}) async {
  setPendingInvite(password ? null : 'a' * 64);
  final router = GoRouter(
    initialLocation: password ? '/set-password' : '/invite/accept',
    routes: [
      GoRoute(
        path: '/invite/accept',
        builder: (_, _) => AcceptInviteScreen(token: pendingInvite ?? ''),
      ),
      GoRoute(
        path: '/set-password',
        builder: (_, _) => const SetPasswordScreen(),
      ),
      for (final path in ['/contexts', '/gestor/home', '/login'])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text(path)),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        invitationRepositoryProvider.overrideWithValue(invites),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _savePassword(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'new-password');
  await tester.enterText(find.byType(TextField).at(1), 'new-password');
  await tester.tap(find.text('Salvar senha'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => setPendingInvite(null));
  testWidgets('invalid acceptance preserves the invalid/expired error', (
    tester,
  ) async {
    final auth = _Auth();
    final invites = _Invites()..invalid = true;
    final router = await _show(tester, auth, invites);
    await tester.tap(find.widgetWithText(FilledButton, 'Aceitar convite'));
    await tester.pumpAndSettle();
    expect(
      find.text('Convite inválido, expirado ou destinado a outro e-mail.'),
      findsOneWidget,
    );
    expect(invites.accepts, 1);
    expect(auth.reloads, 1);
    expect(router.routeInformationProvider.value.uri.path, '/invite/accept');
  });

  testWidgets(
    'accepted invite retries only reload and retains token location',
    (tester) async {
      final auth = _Auth();
      final invites = _Invites();
      final router = await _show(tester, auth, invites);
      final location = router.routeInformationProvider.value.uri;
      auth.failReload = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Aceitar convite'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Convite aceito.'), findsOneWidget);
      expect(find.textContaining('Convite inválido,'), findsNothing);
      expect(router.routeInformationProvider.value.uri, location);
      await tester.tap(find.text('Carregar perfis novamente'));
      await tester.pumpAndSettle();
      expect(invites.accepts, 1);
      auth.failReload = false;
      await tester.tap(find.text('Carregar perfis novamente'));
      await tester.pumpAndSettle();
      expect(invites.accepts, 1);
      expect(invites.token, 'a' * 64);
      expect(pendingInvite, isNull);
      expect(auth.reloads, 4);
      expect(router.routeInformationProvider.value.uri.path, '/contexts');
    },
  );

  for (final needsPassword in [false, true]) {
    testWidgets('accepted invite routes with needsPassword=$needsPassword', (
      tester,
    ) async {
      final auth = _Auth()..needsPassword = needsPassword;
      final invites = _Invites();
      final router = await _show(tester, auth, invites);
      await tester.tap(find.widgetWithText(FilledButton, 'Aceitar convite'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        needsPassword ? '/set-password' : '/contexts',
      );
      expect(invites.accepts, 1);
    });
  }

  testWidgets(
    'saved password retries session without updating password again',
    (tester) async {
      final auth = _Auth();
      final router = await _show(tester, auth, _Invites(), password: true);
      auth.failReload = true;
      await _savePassword(tester);
      expect(find.textContaining('Senha salva.'), findsOneWidget);
      expect(auth.updates, 1);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
        expect(field.enabled, isFalse);
      }
      auth.failReload = false;
      await tester.tap(find.text('Carregar perfis novamente'));
      await tester.pumpAndSettle();
      expect(auth.updates, 1);
      expect(router.routeInformationProvider.value.uri.path, '/gestor/home');
    },
  );

  testWidgets(
    'unconfirmed password completion does not claim no change or bypass gate',
    (tester) async {
      final auth = _Auth()..failUpdate = true;
      final router = await _show(tester, auth, _Invites(), password: true);
      await _savePassword(tester);
      expect(
        find.textContaining('A senha pode já ter sido alterada.'),
        findsOneWidget,
      );
      expect(auth.updates, 1);
      expect(auth.reloads, 1);
      expect(router.routeInformationProvider.value.uri.path, '/set-password');
      expect(find.text('Carregar perfis novamente'), findsNothing);
    },
  );
}
