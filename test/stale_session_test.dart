import 'dart:async';
import 'dart:convert';

import 'package:educador/app/app.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/auth/onboarding_screens.dart';
import 'package:educador/features/auth/screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userJson = {
  'id': 'a9000000-0000-4000-8000-000000000001',
  'aud': 'authenticated',
  'email': 'test@example.test',
  'created_at': '2026-01-01T00:00:00Z',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
};

SupabaseClient _client(MockClient httpClient) => SupabaseClient(
  'https://example.test',
  'public-key',
  httpClient: httpClient,
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

http.Response _json(Object body, int status) => http.Response(
  body is String ? body : jsonEncode(body),
  status,
  headers: {
    'content-type': 'application/json',
    'x-supabase-api-version': '2024-01-01',
  },
);

http.Response _signIn() => _json({
  'access_token': 'test-token',
  'refresh_token': 'test-refresh',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': _userJson,
}, 200);

class _FakeAuth extends AuthRepository {
  _FakeAuth(this._current);
  final Future<AppSession?> Function() _current;
  @override
  Future<AppSession?> current() => _current();
  @override
  void clearRecoverySession() {}
}

Future<ProviderContainer> _pump(WidgetTester tester, _FakeAuth auth) async {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const EducaDorApp()),
  );
  return container;
}

void main() {
  test('a revoked session is cleared and treated as signed out', () async {
    final client = _client(
      MockClient((request) async {
        if (request.url.path.endsWith('/token')) return _signIn();
        if (request.url.path.endsWith('/logout')) return _json({}, 204);
        return _json({
          'code': 'session_not_found',
          'msg': 'Session not found',
        }, 403);
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'password',
    );
    expect(client.auth.currentSession, isNotNull);
    expect(await AuthRepository(client: client).current(), isNull);
    expect(client.auth.currentSession, isNull);
  });

  test('an old failed lookup cannot sign out a newer session', () async {
    final lookup = Completer<http.Response>();
    var tokenCalls = 0;
    final client = _client(
      MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          tokenCalls++;
          final response = jsonDecode(_signIn().body) as Map<String, dynamic>;
          response['access_token'] = 'token-$tokenCalls';
          return _json(response, 200);
        }
        if (request.url.path.endsWith('/user')) return lookup.future;
        return _json({}, 204);
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'password',
    );
    final oldLookup = AuthRepository(client: client).current();
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'password',
    );
    lookup.complete(
      _json({'code': 'session_not_found', 'msg': 'revoked'}, 403),
    );
    await expectLater(oldLookup, throwsA(isA<AuthException>()));
    expect(client.auth.currentSession?.accessToken, 'token-2');
  });

  test('a transient Auth failure keeps the session for retry', () async {
    final client = _client(
      MockClient((request) async {
        if (request.url.path.endsWith('/token')) return _signIn();
        throw http.ClientException('network down');
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'password',
    );
    await expectLater(
      AuthRepository(client: client).current(),
      throwsA(isA<AuthRetryableFetchException>()),
    );
    expect(client.auth.currentSession, isNotNull);
  });

  test('a server error keeps the session for retry', () async {
    final client = _client(
      MockClient((request) async {
        if (request.url.path.endsWith('/token')) return _signIn();
        return _json({'msg': 'unavailable'}, 503);
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'password',
    );
    await expectLater(
      AuthRepository(client: client).current(),
      throwsA(isA<AuthRetryableFetchException>()),
    );
    expect(client.auth.currentSession, isNotNull);
  });

  test('an unclassified Auth error does not sign the session out', () async {
    final client = _client(
      MockClient((request) async {
        if (request.url.path.endsWith('/token')) return _signIn();
        return _json({'code': 'unexpected_failure', 'msg': 'try again'}, 400);
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'password',
    );
    await expectLater(
      AuthRepository(client: client).current(),
      throwsA(isA<AuthApiException>()),
    );
    expect(client.auth.currentSession, isNotNull);
  });

  testWidgets('a cleared session cannot open protected routes', (tester) async {
    final container = await _pump(tester, _FakeAuth(() async => null));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    container.read(routerProvider).go('/gestor/home');
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a transient failure shows retry instead of sign-out', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      _FakeAuth(() async {
        calls++;
        if (calls == 1) {
          throw AuthRetryableFetchException(message: 'network down');
        }
        return null;
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SessionErrorScreen), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(calls, 2);
    expect(find.byType(SessionErrorScreen), findsNothing);
  });

  testWidgets('a hung session load leaves the splash for retry', (
    tester,
  ) async {
    final pending = Completer<AppSession?>();
    addTearDown(() => pending.complete(null));
    await _pump(tester, _FakeAuth(() => pending.future));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(
      SessionController.loadTimeout + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SessionErrorScreen), findsOneWidget);
  });
}
