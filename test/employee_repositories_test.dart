import 'dart:convert';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/employee_providers.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

SupabaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = SupabaseClient(
    'https://example.test',
    'public-key',
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
      id: 'ana',
      fullName: 'Ana',
      email: 'ana@example.test',
      initials: 'A',
    ),
    contexts: [],
    active: AccessContext(
      role: Role.empresa,
      companyId: 'company',
      companyName: 'Company',
    ),
  );
}

class _EmployeeSession extends SessionController {
  @override
  Future<AppSession?> build() async => const AppSession(
    user: User(
      id: 'ana',
      fullName: 'Ana',
      email: 'ana@example.test',
      initials: 'A',
    ),
    contexts: [],
    active: AccessContext(
      role: Role.funcionario,
      companyId: 'company',
      companyName: 'Company',
    ),
  );
}

void main() {
  test(
    'catalog sends scoped search/media/state before page and decodes percentages',
    () async {
      final repo = EmployeeLearningRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rpc/employee_catalog');
          expect(jsonDecode(request.body), {
            'p_company': 'company',
            'p_search': '%_',
            'p_kind': 'video',
            'p_state': 'in_progress',
            'p_offset': 50,
          });
          return http.Response(
            jsonEncode({
              'total': 51,
              'items': [
                {
                  'id': 'course',
                  'title': 'Curso',
                  'state': 'in_progress',
                  'description': null,
                  'cover_key': null,
                  'lesson_count': 4,
                  'completed_count': 1,
                },
              ],
            }),
            200,
          );
        }),
      );
      final page = await repo.catalog(
        'company',
        search: ' %_ ',
        kind: 'video',
        state: 'in_progress',
        offset: 50,
      );
      expect(page.total, 51);
      expect(page.items.single.progress, 0.25);
    },
  );
  test(
    'summary preserves no-data denominators, activity and scoped balance',
    () async {
      final repo = EmployeeLearningRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rpc/employee_summary');
          expect(jsonDecode(request.body), {'p_company': 'company'});
          return http.Response(
            jsonEncode({
              'course_count': 0,
              'completed_course_count': 0,
              'certificate_count': 0,
              'balance': 0,
              'department': null,
              'activity': [
                {'day': '2026-10-01', 'active': false},
              ],
            }),
            200,
          );
        }),
      );
      final result = await repo.summary('company');
      expect(result.completion, isNull);
      expect(result.department, '');
      expect(result.balance, 0);
      expect(result.activity.single.active, isFalse);
    },
  );
  test(
    'lesson reads include playback metadata and persisted resume but no private keys',
    () async {
      final repo = EmployeeLearningRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rpc/employee_lessons');
          expect(jsonDecode(request.body), {
            'p_company': 'company',
            'p_course': 'course',
            'p_offset': 50,
          });
          return http.Response(
            jsonEncode({
              'total': 51,
              'items': [
                {
                  'id': 'lesson',
                  'title': 'Video',
                  'module_id': 'module',
                  'module_title': 'Módulo',
                  'kind': 'video',
                  'status': 'completed',
                  'video_id': 'abcdefghijk',
                  'position_sec': 42,
                },
              ],
            }),
            200,
          );
        }),
      );
      final lesson = (await repo.lessons(
        'company',
        'course',
        offset: 50,
      )).items.single;
      expect(lesson.playable, isTrue);
      expect(lesson.completed, isTrue);
      expect(lesson.positionSec, 42);
    },
  );
  test('certificate history decodes UTC date and historical names', () async {
    final repo = EmployeeLearningRepository(
      client: _client((request) async {
        expect(request.url.path, '/rest/v1/rpc/employee_certificates');
        expect(jsonDecode(request.body), {
          'p_company': 'company',
          'p_offset': 50,
        });
        return http.Response(
          jsonEncode({
            'total': 51,
            'items': [
              {
                'id': 'certificate',
                'code': 'AUD-123ABC',
                'course_id': 'course',
                'course_title': 'Paused course',
                'company_name': 'Company',
                'employee_name': 'Ana',
                'issued_at': '2026-10-01T12:00:00Z',
              },
            ],
          }),
          200,
        );
      }),
    );
    final certificate = (await repo.certificates(
      'company',
      offset: 50,
    )).items.single;
    expect(certificate.courseTitle, 'Paused course');
    expect(certificate.issuedAt, DateTime.utc(2026, 10, 1, 12));
  });
  test(
    'reward catalog is paginated, active only and deterministically ordered',
    () async {
      final repo = EmployeeLearningRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rewards');
          expect(request.url.queryParameters['active'], 'eq.true');
          expect(request.url.queryParameters['offset'], '50');
          expect(request.url.queryParameters['limit'], '50');
          expect(
            request.url.queryParameters['order'],
            'title.asc.nullslast,id.asc.nullslast',
          );
          return http.Response(
            jsonEncode([
              {'id': 'reward', 'title': 'Caneca', 'points_cost': 20},
            ]),
            200,
          );
        }),
      );
      expect((await repo.rewards(offset: 50)).single.cost, 20);
    },
  );
  test('redemption sends expected company and maps server rejection', () async {
    final repo = EmployeeLearningRepository(
      client: _client((request) async {
        expect(request.url.path, '/rest/v1/rpc/redeem_employee_reward');
        expect(jsonDecode(request.body), {
          'p_company': 'company',
          'p_reward': 'reward',
        });
        return http.Response(
          jsonEncode({
            'message': 'Insufficient points',
            'code': 'P0001',
            'details': null,
            'hint': null,
          }),
          400,
        );
      }),
    );
    await expectLater(
      repo.redeem('company', 'reward'),
      throwsA(
        isA<ManagementException>().having(
          (error) => error.message,
          'message',
          'Saldo insuficiente para este resgate.',
        ),
      ),
    );
  });
  test(
    'progress saves through guarded RPC with expected company and no supplied identity',
    () async {
      final repo = ProgressRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rpc/save_employee_progress');
          expect(jsonDecode(request.body), {
            'p_company': 'company',
            'p_lesson': 'lesson',
            'p_position': 90,
            'p_completed': true,
          });
          return http.Response('', 204);
        }),
      );
      await repo.save('company', 'lesson', positionSec: 90, completed: true);
    },
  );
  test(
    'issuer only submits course/company, not user/session or progress claims',
    () async {
      final repo = EmployeeLearningRepository(
        client: _client((request) async {
          expect(request.url.path, '/functions/v1/issue-certificate');
          expect(jsonDecode(request.body), {
            'companyId': 'company',
            'courseId': 'course',
          });
          return http.Response(jsonEncode({'id': 'certificate'}), 200);
        }),
      );
      await repo.issueCertificate('company', 'course');
    },
  );
  test(
    'issuer distinguishes an incomplete course from network/deployment failure',
    () async {
      final repo = EmployeeLearningRepository(
        client: _client(
          (request) async =>
              http.Response(jsonEncode({'error': 'Course incomplete'}), 409),
        ),
      );
      await expectLater(
        repo.issueCertificate('company', 'course'),
        throwsA(isA<CourseIncompleteException>()),
      );
    },
  );
  test(
    'employee data providers reject manager context before issuing requests',
    () async {
      final container = ProviderContainer(
        overrides: [sessionProvider.overrideWith(_Session.new)],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      await expectLater(
        container.read(employeeSummaryProvider.future),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains('Selecione o perfil de funcionário.'),
          ),
        ),
      );
      await expectLater(
        container.read(employeeRankingProvider.future),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains('Selecione o perfil de funcionário.'),
          ),
        ),
      );
    },
  );
  test(
    'old identity/company page queries return empty without accessing backend',
    () async {
      final container = ProviderContainer(
        overrides: [sessionProvider.overrideWith(_EmployeeSession.new)],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      const oldScope = (userId: 'old-person', companyId: 'company');
      expect(
        (await container.read(
          learningCatalogProvider((
            scope: oldScope,
            search: '',
            kind: null,
            state: null,
            offset: 50,
          )).future,
        )).items,
        isEmpty,
      );
      expect(
        (await container.read(
          employeeLessonsProvider((
            scope: oldScope,
            courseId: 'course',
            offset: 50,
          )).future,
        )).items,
        isEmpty,
      );
      expect(
        (await container.read(
          employeeCertificatesProvider((scope: oldScope, offset: 50)).future,
        )).items,
        isEmpty,
      );
      expect(
        await container.read(
          employeeRewardsProvider((scope: oldScope, offset: 50)).future,
        ),
        isEmpty,
      );
    },
  );
}
