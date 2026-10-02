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
      container.read(companyEmployeesProvider.future),
      throwsStateError,
    );
    await expectLater(
      container.read(companyCompletionProvider.future),
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
