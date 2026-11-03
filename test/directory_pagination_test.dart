import 'dart:convert';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/auth/pending_invites.dart';
import 'package:educador/features/content/professional_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class _Invites extends InvitationRepository {
  final calls = <(String, int)>[];
  bool fail = false;
  @override
  Future<List<PendingInvitation>> pending({
    Role? role,
    String? companyId,
    String search = '',
    int offset = 0,
  }) async {
    calls.add((search, offset));
    if (fail) throw StateError('offline');
    return List.generate(
      offset == 0 && search.isEmpty ? 50 : 1,
      (i) => PendingInvitation(
        email: 'person${offset + i}@test.invalid',
        role: Role.empresa,
      ),
    );
  }
}

class _People extends PeopleRepository {
  final calls = <(String, int)>[];
  bool fail = false;
  @override
  Future<List<ProfessionalOption>> platformProfessionals({
    String search = '',
    int offset = 0,
  }) async {
    calls.add((search, offset));
    if (fail) throw StateError('offline');
    return List.generate(
      offset == 0 && search.isEmpty ? 50 : 1,
      (i) =>
          ProfessionalOption(id: '${offset + i}', name: 'Person ${offset + i}'),
    );
  }
}

void main() {
  test('directories use guarded RPCs and literal search parameters', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
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
    await PeopleRepository(
      client: client,
    ).companyManagers('company', search: r'%_\', offset: 50);
    await PeopleRepository(
      client: client,
    ).platformProfessionals(search: r'%_\', offset: 100);
    await InvitationRepository(client: client).pending(
      role: Role.empresa,
      companyId: 'company',
      search: r'%_\',
      offset: 50,
    );
    expect(requests.map((r) => r.url.path), [
      '/rest/v1/rpc/company_managers_page',
      '/rest/v1/rpc/platform_professionals_page',
      '/rest/v1/rpc/directory_pending_invites',
    ]);
    expect(jsonDecode(requests[0].body), {
      'p_company': 'company',
      'p_search': r'%_\',
      'p_offset': 50,
    });
    expect(jsonDecode(requests[1].body), {'p_search': r'%_\', 'p_offset': 100});
    expect(jsonDecode(requests[2].body), {
      'p_role': 'empresa',
      'p_company': 'company',
      'p_search': r'%_\',
      'p_offset': 50,
    });
  });
  test('unconfigured directories do not supply fake data', () async {
    await expectLater(
      PeopleRepository().companyManagers('company'),
      throwsStateError,
    );
    await expectLater(
      PeopleRepository().platformProfessionals(),
      throwsStateError,
    );
    await expectLater(InvitationRepository().pending(), throwsStateError);
  });
  testWidgets(
    'pending invites retain rows on page failure, retry offset and reset search',
    (tester) async {
      final repo = _Invites();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [invitationRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PendingInvitesSection(role: Role.empresa),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.fail = true;
      await tester.ensureVisible(find.text('Carregar mais convites'));
      await tester.tap(find.text('Carregar mais convites'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, ('', 50));
      expect(find.text('person0@test.invalid'), findsOneWidget);
      repo.fail = false;
      final retry = find.text(
        'Não foi possível carregar os convites. Tentar novamente',
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(repo.calls.last, ('', 50));
      expect(find.text('person50@test.invalid'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '%_');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(repo.calls.last, ('%_', 0));
      final count = repo.calls.length;
      await tester.pump(const Duration(seconds: 10));
      expect(repo.calls.length, count);
    },
  );
  testWidgets('professional picker pages and retries explicitly', (
    tester,
  ) async {
    final repo = _People();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [peopleRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => pickProfessional(context, null),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Carregar mais'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    repo.fail = true;
    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, ('', 50));
    repo.fail = false;
    final retry = find.text('Não foi possível carregar. Tentar novamente');
    await tester.dragUntilVisible(
      retry,
      find.byType(ListView),
      const Offset(0, 500),
    );
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repo.calls.last, ('', 50));
    await tester.dragUntilVisible(
      find.text('Person 50'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.enterText(find.byType(TextField), 'literal%');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.calls.last, ('literal%', 0));
  });
}
