import 'dart:convert';

import 'package:educador/data/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('dashboard maps counts, nullable completion and timestamps', () async {
    final client = SupabaseClient(
      'https://example.test',
      'public-test-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/gestor_dashboard');
        return http.Response(
          jsonEncode({
            'company_count': 12,
            'new_company_count': 2,
            'user_count': 30,
            'active_user_count': 8,
            'completion_pct': null,
            'growth': [
              {'month': '2026-09-01', 'companies': 12, 'users': 30},
            ],
            'activities': [
              {
                'id': 'activity',
                'kind': 'company',
                'name': 'Empresa',
                'title': null,
                'occurred_at': '2026-09-01T03:00:00Z',
              },
            ],
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final result = await GestorRepository(client: client).dashboard();
    expect(result.companyCount, 12);
    expect(result.userCount, 30);
    expect(result.completionPct, isNull);
    expect(result.growth.single.month, DateTime(2026, 9));
    expect(result.activities.single.occurredAt, DateTime.utc(2026, 9, 1, 3));
  });

  test(
    'company page sends literal search/status/offset and maps employee counts',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'public-test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/gestor_companies');
          expect(jsonDecode(request.body), {
            'p_search': '%_',
            'p_active': false,
            'p_offset': 50,
          });
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'company',
                  'name': 'Santa Maria',
                  'active': false,
                  'employee_count': 7,
                  'created_at': '2026-09-01T03:00:00Z',
                },
              ],
              'active_count': 10,
              'inactive_count': 3,
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final page = await CompanyRepository(
        client: client,
      ).page(search: ' %_ ', active: false, offset: 50);
      expect(page.items.single.employeeCount, 7);
      expect(page.items.single.initials, 'SM');
      expect(page.activeCount, 10);
      expect(page.inactiveCount, 3);
    },
  );

  test(
    'company lookup queries the ID directly rather than the first page',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'public-test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/companies');
          expect(request.url.queryParameters['id'], 'eq.beyond-page-one');
          return http.Response(
            jsonEncode({
              'id': 'beyond-page-one',
              'name': 'Empresa',
              'active': true,
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      expect(
        (await CompanyRepository(client: client).byId('beyond-page-one')).id,
        'beyond-page-one',
      );
    },
  );

  test(
    'completion query has no period parameters and preserves no-data companies',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'public-test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/gestor_completion');
          expect(jsonDecode(request.body), {'p_offset': 50});
          return http.Response(
            jsonEncode([
              {'company_id': 'a', 'company': 'Same name', 'pct': 37.5},
              {'company_id': 'b', 'company': 'Same name', 'pct': null},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await ReportRepository(
        client: client,
      ).platformCompletion(offset: 50);
      expect(result.first.percent, 37.5);
      expect(result.last.percent, isNull);
      expect(result.last.companyId, 'b');
    },
  );

  test(
    'activity query sends inclusive calendar dates and maps raw counts',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'public-test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/gestor_activity_report');
          expect(jsonDecode(request.body), {
            'p_from': '2026-09-01',
            'p_to': '2026-09-30',
          });
          return http.Response(
            jsonEncode({
              'engagement': [
                {'month': '2026-09-01', 'active_users': 2},
              ],
              'popular_content': [
                {
                  'course_id': 'a',
                  'title': 'Curso',
                  'kind': 'course',
                  'completions': 3,
                },
              ],
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await ReportRepository(client: client).platformActivity(
        from: DateTime(2026, 9, 1, 23),
        to: DateTime(2026, 9, 30, 23),
      );
      expect(result.engagement.single.activeUsers, 2);
      expect(result.popularContent.single.completions, 3);
    },
  );

  test(
    'unconfigured Gestor repositories fail instead of returning mocks',
    () async {
      await expectLater(GestorRepository().dashboard(), throwsStateError);
      await expectLater(CompanyRepository().page(), throwsStateError);
      for (final id in ['c-santa-maria', 'unknown-company']) {
        await expectLater(
          CompanyRepository().byId(id),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Configure o Supabase para carregar empresas.',
            ),
          ),
        );
      }
      await expectLater(
        ReportRepository().platformCompletion(),
        throwsStateError,
      );
    },
  );
}
