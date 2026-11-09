import 'dart:convert';

import 'package:educador/core/recovery_link.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/recovery_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _id = 'a9000000-0000-4000-8000-000000000009';
const _sessionId = 'b9000000-0000-4000-8000-000000000009';

Map<String, Object?> _user({bool mfa = false}) => {
  'id': _id,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'recovery@example.test',
  'created_at': '2026-01-01T00:00:00Z',
  'app_metadata': <String, Object?>{},
  'user_metadata': <String, Object?>{},
  if (mfa)
    'factors': [
      {
        'id': 'factor',
        'factor_type': 'totp',
        'status': 'verified',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      },
    ],
};

Map<String, Object?> _session({
  String method = 'otp',
  String aal = 'aal1',
  bool mfa = false,
  String id = _sessionId,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final jwt =
      '${encode({'alg': 'HS256'})}.${encode({
        'sub': _id,
        'session_id': id,
        'aal': aal,
        'amr': [
          {'method': method, 'timestamp': now},
        ],
        'exp': now + 3600,
      })}.test';
  return {
    'access_token': jwt,
    'refresh_token': 'test-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': _user(mfa: mfa),
  };
}

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {
    'content-type': 'application/json',
    'x-supabase-api-version': '2024-01-01',
  },
);

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://example.test',
      'public-test-key',
      httpClient: MockClient(handler),
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

void main() {
  test(
    'request uses the fixed callback and never exposes whether an account exists',
    () async {
      final calls = <http.Request>[];
      final client = _client((r) async {
        calls.add(r);
        return _json({});
      });
      addTearDown(client.dispose);
      final repo = AuthRepository(client: client);
      await repo.requestPasswordReset('  account@example.test  ');
      await repo.requestPasswordReset('unknown@example.test');
      expect(calls.length, 2);
      expect(calls.first.url.path, '/auth/v1/recover');
      expect(
        calls.first.url.queryParameters['redirect_to'],
        passwordRecoveryRedirectUrl,
      );
      expect(jsonDecode(calls.first.body)['email'], 'account@example.test');
      expect(jsonDecode(calls.first.body)['code_challenge'], isNull);
      expect(client.auth.currentUser, isNull);
    },
  );

  test(
    'recipient cooldown is not returned as an account-existence signal',
    () async {
      final client = _client(
        (_) async => _json({
          'msg': 'wait',
          'code': 'over_email_send_rate_limit',
        }, status: 429),
      );
      addTearDown(client.dispose);
      await AuthRepository(
        client: client,
      ).requestPasswordReset('account@example.test');
    },
  );

  test('invalid recovery hashes do not make requests', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      return _json({});
    });
    addTearDown(client.dispose);
    await expectLater(
      AuthRepository(client: client).verifyRecoveryToken('invalid'),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test(
    'verification binds recovery intent to the authenticated session and survives repository recreation',
    () async {
      final paths = <String>[];
      final client = _client((r) async {
        paths.add(r.url.path);
        if (r.url.path.endsWith('/verify')) {
          final body = jsonDecode(r.body) as Map;
          expect(body['type'], 'recovery');
          expect(body['token_hash'], 'a' * 64);
          expect(body.containsKey('email'), isFalse);
          expect(body.containsKey('phone'), isFalse);
          return _json(_session());
        }
        expect(r.url.path, '/auth/v1/user');
        expect(r.method, 'GET');
        return _json(_user());
      });
      addTearDown(client.dispose);
      final intent = RecoveryIntentStore();
      final repo = AuthRepository(client: client, recoveryIntent: intent);
      await repo.verifyRecoveryToken('a' * 64);
      expect(intent.read(), _sessionId);
      expect((await repo.current())!.recoveringPassword, isTrue);
      expect(
        (await AuthRepository(
          client: client,
          recoveryIntent: intent,
        ).current())!.recoveringPassword,
        isTrue,
      );
      expect(paths.where((path) => path.startsWith('/rest/')), isEmpty);
    },
  );

  for (final aal in ['aal1', 'aal2']) {
    test(
      'enrolled recovery requires MFA before password mutation: $aal',
      () async {
        var writes = 0;
        final client = _client((r) async {
          if (r.url.path.endsWith('/verify')) {
            return _json(_session(aal: aal, mfa: true));
          }
          expect(r.url.path, '/auth/v1/user');
          if (r.method == 'PUT') {
            writes++;
            expect(jsonDecode(r.body)['password'], 'new-password');
          }
          return _json(_user(mfa: true));
        });
        addTearDown(client.dispose);
        final repo = AuthRepository(client: client);
        await repo.verifyRecoveryToken('a' * 64);
        final current = (await repo.current())!;
        expect(current.recoveringPassword, isTrue);
        expect(current.needsMfa, aal == 'aal1');
        if (aal == 'aal1') {
          await expectLater(
            repo.updateRecoveredPassword('new-password'),
            throwsStateError,
          );
        } else {
          await repo.updateRecoveredPassword('new-password');
        }
        expect(writes, aal == 'aal1' ? 0 : 1);
      },
    );
  }

  test(
    'a stale marker or ordinary password session cannot become a recovery session',
    () async {
      final client = _client((r) async {
        if (r.url.path.endsWith('/token')) {
          return _json(_session(method: 'password', mfa: true));
        }
        expect(r.url.path, '/auth/v1/user');
        expect(r.method, 'GET');
        return _json(_user(mfa: true));
      });
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'recovery@example.test',
        password: 'old-password',
      );
      final intent = RecoveryIntentStore()..save(_sessionId);
      final repo = AuthRepository(client: client, recoveryIntent: intent);
      expect((await repo.current())!.recoveringPassword, isFalse);
      await expectLater(
        repo.updateRecoveredPassword('new-password'),
        throwsStateError,
      );
      intent.save('b9000000-0000-4000-8000-000000000010');
      expect((await repo.current())!.recoveringPassword, isFalse);
      expect(intent.read(), isNull);
    },
  );

  test(
    'fragment parser rejects query credentials, duplicates and malformed links',
    () {
      final hash = 'a' * 64;
      final sha224Hash = 'b' * 56;
      expect(
        recoveryTokenFromUri(
          Uri.parse('/recover/complete#token_hash=$sha224Hash'),
        ),
        sha224Hash,
      );
      expect(
        recoveryTokenFromUri(Uri.parse('/recover/complete#token_hash=$hash')),
        hash,
      );
      expect(
        recoveryTokenFromUri(
          Uri.parse('/recover/complete#token_hash=pkce_$hash'),
        ),
        'pkce_$hash',
      );
      for (final value in [
        '/recover/complete?token_hash=$hash',
        '/recover/complete#token_hash=short',
        '/recover/complete#token_hash=$hash&token_hash=$hash',
        '/login#token_hash=$hash',
      ]) {
        expect(recoveryTokenFromUri(Uri.parse(value)), isNull);
      }
    },
  );
}
