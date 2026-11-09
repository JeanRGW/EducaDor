import 'dart:convert';

import 'package:educador/core/invite_link.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'unsupported Auth types and missing verified sessions fail closed',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-public-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = AuthRepository(client: client);
      await expectLater(
        repo.verifyInviteToken(
          InviteAuthLink(
            tokenHash: 'b' * 64,
            type: 'recovery',
            token: 'a' * 64,
          ),
        ),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
      await expectLater(
        repo.verifyInviteToken(
          InviteAuthLink(tokenHash: 'b' * 64, type: 'invite', token: 'a' * 64),
        ),
        throwsStateError,
      );
      expect(requests, hasLength(1));
    },
  );
  for (final type in ['invite', 'magiclink']) {
    test(
      'explicit verification POSTs the $type hash to configured Auth',
      () async {
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'https://example.test',
          'test-public-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode({'msg': 'Expired test token', 'code': 'otp_expired'}),
              403,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        final link = InviteAuthLink(
          tokenHash: 'b' * 64,
          type: type,
          token: 'a' * 64,
        );
        expect(requests, isEmpty);
        await expectLater(
          AuthRepository(client: client).verifyInviteToken(link),
          throwsA(isA<AuthException>()),
        );
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.url.origin, 'https://example.test');
        expect(requests.single.url.path, '/auth/v1/verify');
        expect(requests.single.url.queryParameters, isEmpty);
        final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
        expect(body['token_hash'], link.tokenHash);
        expect(body['type'], type);
        expect(body['redirect_to'], isNull);
        expect(requests.single.body, isNot(contains(link.token)));
      },
    );
  }
}
