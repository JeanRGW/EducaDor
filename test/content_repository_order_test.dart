import 'dart:convert';
import 'package:educador/data/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'module and lesson reads explicitly match ascending database mutation order',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.test',
        'public-test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = ContentRepository(client: client);
      await repo.modules('course', offset: 50);
      await repo.moduleLessons('module', offset: 50);
      for (final request in requests) {
        expect(
          request.url.queryParameters['order'],
          'position.asc.nullslast,id.asc.nullslast',
        );
        expect(request.url.queryParameters['offset'], '50');
        expect(request.url.queryParameters['limit'], '50');
      }
    },
  );
  test(
    'deletions use the guarded RPC, not client-side cascade logic',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.test',
        'public-test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204, request: request);
        }),
      );
      addTearDown(client.dispose);
      final repo = ContentRepository(client: client);
      for (final kind in ['course', 'module', 'lesson']) {
        await repo.deleteContent(kind, 'id');
      }
      for (final (index, kind) in ['course', 'module', 'lesson'].indexed) {
        expect(requests[index].url.path, '/rest/v1/rpc/delete_content');
        expect(jsonDecode(requests[index].body), {
          'p_kind': kind,
          'p_id': 'id',
        });
      }
    },
  );
}
