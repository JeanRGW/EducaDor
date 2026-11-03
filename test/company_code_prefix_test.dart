import 'dart:convert';

import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/gestor/company_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async => null;
  @override
  Future<AppSession?> reload() async => null;
}

class _Companies extends CompanyRepository {
  final String prefix;
  final writes = <Map<String, String>>[];
  _Companies(this.prefix);
  @override
  Future<Company> byId(String id) async => Company(
    id: id,
    name: 'Empresa',
    codePrefix: prefix,
    cnpj: '',
    responsibleName: '',
    email: '',
    phone: '',
    address: '',
    city: '',
    state: '',
    field: '',
    employeeCount: 0,
    active: true,
    registeredAt: '',
    initials: 'E',
  );
  @override
  Future<void> update(String id, Map<String, String> fields) async {
    writes.add(fields);
  }
}

void main() {
  test(
    'company reads map prefix and updates forward optional field via RPC',
    () async {
      final writes = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.test',
        'public-test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('update_company')) {
            writes.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response('', 204, request: request);
          }
          return http.Response(
            jsonEncode({
              'id': 'company',
              'name': 'Empresa',
              'active': true,
              'code_prefix': 'ACME9',
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = CompanyRepository(client: client);
      expect((await repo.byId('company')).codePrefix, 'ACME9');
      await repo.update('company', {'name': 'Empresa', 'code_prefix': 'NEW12'});
      await repo.update('company', {'name': 'Empresa'});
      expect(writes.first['p_fields'], {
        'name': 'Empresa',
        'code_prefix': 'NEW12',
      });
      expect(writes.last['p_fields'], {'name': 'Empresa'});
    },
  );

  for (final prefix in ['EDU', 'legacy-prefix-too-long']) {
    testWidgets('editor preserves unchanged $prefix and validates new prefix', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Companies(prefix);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companyRepositoryProvider.overrideWithValue(repo),
            sessionProvider.overrideWith(_Session.new),
          ],
          child: const MaterialApp(
            home: CompanyDetailScreen(companyId: 'company'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == prefix,
      );
      final controller = tester.widget<TextFormField>(field).controller!;
      final save = find.text('Salvar dados da empresa');
      Future<void> saveDraft() async {
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }

      await saveDraft();
      expect(repo.writes.single.containsKey('code_prefix'), isFalse);
      repo.writes.clear();
      for (final invalid in ['', 'lower', 'A-B', 'ABCDEFGHIJKLM', 'ÁBC']) {
        controller.text = invalid;
        await saveDraft();
        expect(repo.writes, isEmpty);
        expect(
          find.text('Use de 1 a 12 letras maiúsculas ou números.'),
          findsOneWidget,
        );
      }
      controller.text = 'ABC123DEF456';
      await saveDraft();
      expect(repo.writes.single['code_prefix'], 'ABC123DEF456');
      expect(tester.takeException(), isNull);
    });
  }
}
