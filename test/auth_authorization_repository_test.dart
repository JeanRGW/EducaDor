import 'dart:convert';

import 'package:educador/data/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('session loads own profile including optional gender through RPC', () async {
    final user = {
      'id': 'a9000000-0000-4000-8000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'security@example.test',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
    };
    final client = SupabaseClient('https://example.test', 'public-test-key',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object body;
        if (path.endsWith('/token')) {
          body = {'access_token': 'test-token', 'refresh_token': 'test-refresh',
            'token_type': 'bearer', 'expires_in': 3600, 'user': user};
        } else if (path.endsWith('/user')) {
          body = user;
        } else if (path.endsWith('/own_profile')) {
          expect(request.body, 'null');
          body = [{'id': user['id'], 'full_name': 'Ana Silva', 'email': user['email'],
            'needs_password': false, 'gender': 'female'}];
        } else {
          expect(path, anyOf('/rest/v1/rpc/available_contexts', '/rest/v1/rpc/selected_context'));
          body = [];
        }
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
      }));
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(email: 'security@example.test', password: 'password');
    final session = await AuthRepository(client: client).current();
    expect(session?.user.fullName, 'Ana Silva');
    expect(session?.user.gender?.name, 'female');
  });
  for (final failAuth in [false, true]) {
    test(
      'password completion follows successful Auth update ($failAuth)',
      () async {
        final paths = <String>[];
        final user = {
          'id': 'a9000000-0000-4000-8000-000000000001',
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'security@example.test',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        };
        final client = SupabaseClient(
          'https://example.test',
          'public-test-key',
          httpClient: MockClient((request) async {
            final path = request.url.path;
            paths.add(path);
            var status = 200;
            Object body = {};
            if (path.endsWith('/token')) {
              body = {
                'access_token': 'test-token',
                'refresh_token': 'test-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': user,
              };
            } else if (path.endsWith('/user')) {
              expect(jsonDecode(request.body)['password'], 'new-password');
              status = failAuth ? 422 : 200;
              body = failAuth
                  ? {'msg': 'Rejected password', 'code': 'weak_password'}
                  : user;
            } else {
              expect(path, '/rest/v1/rpc/complete_password_setup');
              expect(request.method, 'POST');
              // Empty-argument RPCs carry a null payload.
              expect(request.body, 'null');
              body = 'null';
            }
            return http.Response(
              body is String ? body : jsonEncode(body),
              status,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.signInWithPassword(
          email: 'security@example.test',
          password: 'old-password',
        );
        paths.clear();
        final repo = AuthRepository(client: client);
        if (failAuth) {
          await expectLater(
            repo.updatePassword('new-password'),
            throwsA(isA<AuthException>()),
          );
        } else {
          await repo.updatePassword('new-password');
        }
        expect(paths, [
          '/auth/v1/user',
          if (!failAuth) '/rest/v1/rpc/complete_password_setup',
        ]);
      },
    );
  }
}
