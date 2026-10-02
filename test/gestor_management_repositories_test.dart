import 'dart:convert';

import 'package:educador/data/models/models.dart';
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

class _Auth extends AuthRepository {
  String name = 'Ana Silva';
  @override
  Future<AppSession?> current() async => AppSession(
    user: User(
      id: 'me',
      fullName: name,
      email: 'ana@example.test',
      initials: name.split(' ').map((s) => s[0]).join(),
    ),
    contexts: const [
      AccessContext(role: Role.gestor, companyName: 'Plataforma'),
    ],
    active: const AccessContext(role: Role.gestor, companyName: 'Plataforma'),
  );
}

void main() {
  test(
    'session refresh replaces identity while retaining active context',
    () async {
      final auth = _Auth();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      auth.name = 'Marina Oliveira';
      await container.read(sessionProvider.notifier).reload();
      final session = container.read(sessionProvider).value!;
      expect(session.user.fullName, 'Marina Oliveira');
      expect(session.user.initials, 'MO');
      expect(session.role, Role.gestor);
      expect(session.contexts.length, 1);
    },
  );
  test('company mutations use guarded RPCs and never update grants', () async {
    final requests = <http.Request>[];
    final repo = CompanyRepository(
      client: _client((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );
    await repo.update('company', {
      'name': 'Edited',
      'email': 'contact@example.test',
    });
    await repo.setActive('company', false);
    expect(requests.map((r) => r.url.path), [
      '/rest/v1/rpc/update_company',
      '/rest/v1/rpc/set_company_active',
    ]);
    expect(jsonDecode(requests[0].body), {
      'p_company': 'company',
      'p_fields': {'name': 'Edited', 'email': 'contact@example.test'},
    });
    expect(jsonDecode(requests[1].body), {
      'p_company': 'company',
      'p_active': false,
    });
  });

  test(
    'manager listing paginates server-side and revokes only selected scope',
    () async {
      final requests = <http.Request>[];
      final repo = PeopleRepository(
        client: _client((request) async {
          requests.add(request);
          if (request.url.path.endsWith('gestor_managers')) {
            return http.Response(
              jsonEncode([
                {
                  'id': 'person',
                  'full_name': 'Ana Silva',
                  'email': 'ana@example.test',
                },
              ]),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      final people = await repo.managers(
        companyId: 'company',
        search: ' Ana ',
        offset: 50,
      );
      expect(people.single.initials, 'AS');
      expect(jsonDecode(requests[0].body), {
        'p_company': 'company',
        'p_search': 'Ana',
        'p_offset': 50,
      });
      await repo.revokeAccess('person', companyId: 'company');
      await repo.revokeAccess('person');
      expect(jsonDecode(requests[1].body), {
        'p_user': 'person',
        'p_company': 'company',
      });
      expect(jsonDecode(requests[2].body), {
        'p_user': 'person',
        'p_company': null,
      });
    },
  );

  for (final scope in ['platform', 'company']) {
    test('last $scope gestor rejection is actionable', () async {
      final repo = PeopleRepository(
        client: _client(
          (request) async => http.Response(
            jsonEncode({
              'code': 'P0001',
              'message': 'Last $scope gestor',
              'details': null,
              'hint': null,
            }),
            400,
          ),
        ),
      );
      await expectLater(
        repo.revokeAccess(
          'person',
          companyId: scope == 'company' ? 'company' : null,
        ),
        throwsA(
          isA<ManagementException>().having(
            (e) => e.message,
            'message',
            contains('pelo menos um gestor'),
          ),
        ),
      );
    });
  }

  test(
    'profile update cannot send user ID, email or authorization fields',
    () async {
      final repo = ProfileRepository(
        client: _client((request) async {
          expect(request.url.path, '/rest/v1/rpc/update_own_profile');
          expect(jsonDecode(request.body), {
            'p_name': 'Ana Silva',
            'p_phone': '123',
            'p_birth_date': '1990-01-01',
            'p_address': 'Rua A',
          });
          return http.Response('', 204);
        }),
      );
      await repo.update(
        const OwnProfile(
          fullName: ' Ana Silva ',
          email: 'ignored@example.test',
          phone: ' 123 ',
          birthDate: '1990-01-01',
          address: ' Rua A ',
        ),
      );
    },
  );

  test(
    'metadata and video updates retain row IDs without sending access/progress',
    () async {
      final requests = <http.Request>[];
      final repo = ContentRepository(
        client: _client((request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      );
      await repo.updateMetadata(
        'course',
        title: ' Edited ',
        description: ' Description ',
        coverKey: 'covers/old.webp',
        responsibleId: 'author',
      );
      await repo.updateLesson(
        'lesson',
        moduleTitle: ' Module ',
        title: ' Lesson ',
        videoId: 'abcdefghijk',
      );
      expect(jsonDecode(requests[0].body), {
        'p_course': 'course',
        'p_title': 'Edited',
        'p_description': 'Description',
        'p_cover_key': 'covers/old.webp',
        'p_responsible_id': 'author',
      });
      expect(jsonDecode(requests[1].body), {
        'p_lesson': 'lesson',
        'p_module_title': 'Module',
        'p_title': 'Lesson',
        'p_video_id': 'abcdefghijk',
      });
    },
  );

  test(
    'course detail retains cover key and responsible after revocation',
    () async {
      final repo = ContentRepository(
        client: _client((request) async {
          final data = request.url.path.endsWith('profiles')
              ? {'full_name': 'Former Gestor'}
              : {
                  'id': 'course',
                  'title': 'Course',
                  'description': 'Description',
                  'cover_key': 'legacy-cover.webp',
                  'status': 'paused',
                  'all_companies': false,
                  'responsible_id': 'former-gestor',
                };
          return http.Response(jsonEncode(data), 200);
        }),
      );
      final detail = await repo.detail('course');
      expect(detail.coverKey, 'legacy-cover.webp');
      expect(detail.responsible!.name, 'Former Gestor');
      expect(detail.platformEnabled, isFalse);
      expect(detail.allCompanies, isFalse);
    },
  );

  test('audience reads use a single guarded RPC', () async {
    final repo = ContentRepository(
      client: _client((request) async {
        expect(request.url.path, '/rest/v1/rpc/gestor_course_audience');
        expect(jsonDecode(request.body), {'p_course': 'course'});
        return http.Response(
          jsonEncode([
            {
              'all_companies': false,
              'company_ids': ['a', 'b'],
            },
          ]),
          200,
        );
      }),
    );
    final audience = await repo.audience('course');
    expect(audience.allCompanies, isFalse);
    expect(audience.companyIds, ['a', 'b']);
    expect(audience.label, '2 empresas selecionadas');
  });

  test('lesson reads paginate within the selected course', () async {
    final repo = ContentRepository(
      client: _client((request) async {
        expect(request.url.path, '/rest/v1/rpc/gestor_course_lessons');
        expect(jsonDecode(request.body), {
          'p_course': 'course',
          'p_offset': 50,
        });
        return http.Response(
          jsonEncode([
            {
              'id': 'lesson',
              'title': 'Lesson',
              'kind': 'video',
              'video_id': 'abcdefghijk',
              'module_title': 'Module',
            },
          ]),
          200,
        );
      }),
    );
    expect(
      (await repo.editableLessons('course', offset: 50)).single.moduleTitle,
      'Module',
    );
  });

  test('new management reads fail closed without Supabase', () async {
    await expectLater(PeopleRepository().managers(), throwsStateError);
    await expectLater(ProfileRepository().own(), throwsStateError);
    await expectLater(ContentRepository().detail('course'), throwsStateError);
  });
}
