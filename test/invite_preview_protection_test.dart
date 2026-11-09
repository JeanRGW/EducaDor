import 'dart:async';

import 'package:educador/app/theme.dart';
import 'package:educador/core/invite_link.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/auth/invite_start_screen.dart';
import 'package:educador/features/auth/onboarding_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _hash = 'b' * 64;
final _token = 'a' * 64;
String _location({String type = 'invite'}) =>
    '/invite/start#token_hash=$_hash&type=$type&token=$_token';

class _Auth extends AuthRepository {
  int verifications = 0;
  bool failVerify = false;
  bool failReload = false;
  InviteAuthLink? verified;
  Completer<void>? pendingVerification;

  @override
  Future<void> verifyInviteToken(InviteAuthLink link) async {
    verifications++;
    await pendingVerification?.future;
    if (failVerify) throw StateError('Expired');
    verified = link;
  }

  @override
  Future<AppSession?> current() async {
    if (failReload) throw StateError('Offline');
    if (verified == null) return null;
    return const AppSession(
      user: User(
        id: 'user',
        fullName: 'Ana',
        email: 'ana@example.test',
        initials: 'A',
      ),
      contexts: [],
      needsPassword: true,
    );
  }
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  _Auth auth,
  String location,
) async {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  router.go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('parser accepts only fragment credentials and supported Auth types', () {
    for (final type in ['invite', 'magiclink']) {
      final link = InviteAuthLink.fromUri(Uri.parse(_location(type: type)))!;
      expect(link.tokenHash, _hash);
      expect(link.token, _token);
      expect(link.type, type);
    }
    for (final location in [
      '/invite/start',
      '/invite/start?token_hash=$_hash&type=invite&token=$_token',
      '${_location()}&token=duplicate',
      '${_location()}&extra=value',
      _location(type: 'recovery'),
      '/invite/start#token_hash=bad&type=invite&token=$_token',
      '/invite/start#token_hash=$_hash&type=invite&token=bad',
      '/invite/start#%zz',
    ]) {
      expect(InviteAuthLink.fromUri(Uri.parse(location)), isNull);
    }
  });

  for (final type in ['invite', 'magiclink']) {
    testWidgets('preview/reloads never verify $type; only Continue does', (
      tester,
    ) async {
      final auth = _Auth();
      final container = await _show(tester, auth, _location(type: type));
      expect(find.byType(InviteStartScreen), findsOneWidget);
      expect(auth.verifications, 0);
      container.read(routerProvider).refresh();
      await tester.pumpAndSettle();
      expect(auth.verifications, 0);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(auth.verifications, 1);
      expect(auth.verified!.type, type);
      expect(find.byType(AcceptInviteScreen), findsOneWidget);
      expect(
        container
            .read(routerProvider)
            .routeInformationProvider
            .value
            .uri
            .toString(),
        '/invite/accept?token=$_token',
      );
    });
  }

  testWidgets('failed reload retries without consuming the Auth token again', (
    tester,
  ) async {
    final auth = _Auth();
    await _show(tester, auth, _location());
    auth.failReload = true;
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Link confirmado.'), findsOneWidget);
    expect(auth.verifications, 1);
    auth.failReload = false;
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(auth.verifications, 1);
    expect(find.byType(AcceptInviteScreen), findsOneWidget);
  });

  testWidgets('expired token stays on the landing page with safe feedback', (
    tester,
  ) async {
    final auth = _Auth()..failVerify = true;
    await _show(tester, auth, _location());
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Este link expirou'), findsOneWidget);
    expect(find.byType(InviteStartScreen), findsOneWidget);
    expect(find.textContaining(_hash), findsNothing);
    expect(find.textContaining(_token), findsNothing);
  });

  testWidgets('invalid links have no Continue action', (tester) async {
    final auth = _Auth();
    await _show(tester, auth, '/invite/start');
    expect(find.text('Link de convite inválido'), findsOneWidget);
    expect(find.text('Continuar'), findsNothing);
    expect(auth.verifications, 0);
  });

  testWidgets(
    'a delayed failure from an old link cannot replace the new link feedback',
    (tester) async {
      final pending = Completer<void>();
      final auth = _Auth()..pendingVerification = pending;
      final container = await _show(tester, auth, _location());
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      final newLocation =
          '/invite/start#token_hash=${'c' * 64}&type=invite&token=${'d' * 64}';
      container.read(routerProvider).go(newLocation);
      await tester.pumpAndSettle();
      auth.failVerify = true;
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Este link expirou'), findsNothing);
      auth.pendingVerification = null;
      auth.failVerify = false;
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(auth.verified!.tokenHash, 'c' * 64);
      expect(find.byType(AcceptInviteScreen), findsOneWidget);
    },
  );

  testWidgets('landing fits narrow screens and enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProviderScope(
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: InviteStartScreen(
              link: InviteAuthLink.fromUri(Uri.parse(_location())),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Continuar'), 100);
    expect(find.text('Continuar'), findsOneWidget);
  });
}
