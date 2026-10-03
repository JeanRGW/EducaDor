import 'dart:convert';

import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/company_providers.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) {
  final client = SupabaseClient(
    'https://example.test',
    'public-test-key',
    httpClient: MockClient((request) async {
      final response = await handler(request);
      return http.Response(
        response.body,
        response.statusCode,
        request: request,
        headers: {'content-type': 'application/json', ...response.headers},
      );
    }),
  );
  addTearDown(client.dispose);
  return client;
}

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async => const AppSession(
    user: User(
      id: 'person',
      fullName: 'Ana',
      email: 'ana@example.test',
      initials: 'A',
    ),
    contexts: [],
    active: AccessContext(
      role: Role.funcionario,
      companyId: 'company-a',
      companyName: 'Empresa',
    ),
  );
}

void main() {
  test(
    'dashboard decodes exact aggregates, zero months and company-wide highlights',
    () async {
      final repo = CompanyDataRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rpc/company_dashboard');
          expect(jsonDecode(request.body), {'p_company': 'company-a'});
          return http.Response(
            jsonEncode({
              'employee_count': 125,
              'active_course_count': 0,
              'certificate_count': 7,
              'completion_pct': null,
              'engagement': [
                {'month': '2026-09-01', 'active_users': 0},
              ],
              'highlights': [
                {
                  'user_id': 'person',
                  'full_name': 'Ana Silva',
                  'email': 'ana@example.test',
                  'dept': 'RH',
                  'job_title': null,
                  'pct': 100,
                },
              ],
            }),
            200,
          );
        }),
      );
      final result = await repo.dashboard('company-a');
      expect(result.employeeCount, 125);
      expect(result.activeCourseCount, 0);
      expect(result.certificateCount, 7);
      expect(result.completionPct, isNull);
      expect(result.engagement.single.activeUsers, 0);
      expect(result.highlights.single.fullName, 'Ana Silva');
      expect(result.highlights.single.status, EmployeeStatus.unknown);
    },
  );

  test(
    'employee page sends server search and offset and decodes scoped activity',
    () async {
      final repo = EmployeeRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rpc/company_employees');
          expect(jsonDecode(request.body), {
            'p_company': 'company-a',
            'p_search': '%_',
            'p_offset': 50,
          });
          return http.Response(
            jsonEncode({
              'total_count': 125,
              'filtered_count': 51,
              'items': [
                {
                  'user_id': 'person',
                  'full_name': 'Ana Silva',
                  'email': 'ana@example.test',
                  'dept': 'RH',
                  'job_title': null,
                  'pct': 0,
                  'last_activity_at': '2026-10-01T12:30:00+00:00',
                },
                {
                  'user_id': 'other',
                  'full_name': 'Bruno',
                  'email': 'bruno@example.test',
                  'dept': null,
                  'job_title': null,
                  'pct': null,
                  'last_activity_at': null,
                },
              ],
            }),
            200,
          );
        }),
      );
      final result = await repo.page('company-a', search: ' %_ ', offset: 50);
      expect(result.totalCount, 125);
      expect(result.filteredCount, 51);
      expect(
        result.items.map((item) => item.status),
        everyElement(EmployeeStatus.unknown),
      );
      expect(
        result.items.first.lastActivityAt,
        DateTime.utc(2026, 10, 1, 12, 30),
      );
      expect(result.items.first.hasCompletion, isTrue);
      expect(result.items.last.lastActivityAt, isNull);
      expect(result.items.last.hasCompletion, isFalse);
    },
  );

  test(
    'company completion uses the existing guarded view and preserves null',
    () async {
      final repo = ReportRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/completion_by_company');
          expect(request.url.queryParameters['company_id'], 'eq.company-a');
          expect(request.url.queryParameters['select'], 'pct');
          return http.Response(jsonEncode({'pct': null}), 200);
        }),
      );
      expect(await repo.completion('company-a'), isNull);
    },
  );

  test('department reads are company-scoped, ordered and paginated', () async {
    final repo = ReportRepository(
      client: _client((request) async {
        expect(request.url.path, '/rest/v1/completion_by_dept');
        expect(request.url.queryParameters['company_id'], 'eq.company-a');
        expect(
          request.url.queryParameters['order'],
          'department.asc.nullslast',
        );
        expect(request.url.queryParameters['offset'], '50');
        expect(request.url.queryParameters['limit'], '50');
        return http.Response(
          jsonEncode([
            {'department': 'RH', 'pct': 60},
            {'department': null, 'pct': null},
          ]),
          200,
        );
      }),
    );
    final rows = await repo.departmentCompletion('company-a', offset: 50);
    expect(rows.first.key, 'RH');
    expect(rows.first.value, 60);
    expect(rows.last.key, 'Sem departamento');
    expect(rows.last.value, isNull);
  });

  test(
    'employees decode a table response and retain unknown completion',
    () async {
      final repo = EmployeeRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rpc/employee_completion');
          expect(jsonDecode(request.body), {'p_company': 'company-a'});
          return http.Response(
            jsonEncode([
              {
                'user_id': 'person',
                'full_name': 'Ana Silva',
                'email': 'ana@example.test',
                'dept': 'RH',
                'job_title': 'Analista',
                'pct': null,
              },
              {
                'user_id': 'other',
                'full_name': 'Bruno',
                'email': 'bruno@example.test',
                'dept': null,
                'job_title': null,
                'pct': 0,
              },
            ]),
            200,
          );
        }),
      );
      final rows = await repo.all('company-a');
      expect(rows.first.initials, 'AS');
      expect(
        rows.map((row) => row.status),
        everyElement(EmployeeStatus.unknown),
      );
      expect(rows.first.hasCompletion, isFalse);
      expect(rows.last.hasCompletion, isTrue);
      expect(rows.last.completionPct, 0);
      expect(rows.first.lastActivity, isEmpty);
    },
  );

  test('company data providers cannot read from an employee context', () async {
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWith(_Session.new)],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    await expectLater(
      container.read(
        companyEmployeesProvider((
          companyId: 'company-a',
          search: '',
          offset: 0,
        )).future,
      ),
      throwsStateError,
    );
    await expectLater(
      container.read(companyDashboardProvider.future),
      throwsStateError,
    );
    await expectLater(
      container.read(companyIdentityProvider.future),
      throwsStateError,
    );
    await expectLater(
      container.read(
        companyDepartmentsProvider((companyId: 'company-a', offset: 0)).future,
      ),
      throwsStateError,
    );
  });

  test(
    'company data reads fail clearly instead of displaying production mocks',
    () async {
      await expectLater(
        EmployeeRepository().all('company-a'),
        throwsStateError,
      );
      await expectLater(
        EmployeeRepository().page('company-a'),
        throwsStateError,
      );
      await expectLater(
        CompanyDataRepository().dashboard('company-a'),
        throwsStateError,
      );
      await expectLater(
        ReportRepository().completion('company-a'),
        throwsStateError,
      );
      await expectLater(
        ReportRepository().departmentCompletion('company-a'),
        throwsStateError,
      );
    },
  );
}
