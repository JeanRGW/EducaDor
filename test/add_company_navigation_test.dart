import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/gestor/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Company _company(String name) => Company(
  id: 'company-1',
  name: name,
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
  registeredAt: '2026-11-16',
  initials: 'EM',
);

class _Companies extends CompanyRepository {
  final names = <String>[];

  @override
  Future<Company> create({required String name}) async {
    names.add(name);
    return _company(name);
  }
}

void main() {
  for (final pushed in [false, true]) {
    for (final save in [false, true]) {
      testWidgets(
        'add company ${save ? 'success' : 'back'} navigates safely (pushed: $pushed)',
        (tester) async {
          final companies = _Companies();
          final router = GoRouter(
            initialLocation: pushed ? '/gestor/empresas' : '/add',
            routes: [
              GoRoute(
                path: '/gestor/empresas',
                builder: (context, _) => Scaffold(
                  body: TextButton(
                    onPressed: () => context.push('/add'),
                    child: const Text('Empresas'),
                  ),
                ),
              ),
              GoRoute(path: '/add', builder: (_, _) => const AddCompanyScreen()),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                companyRepositoryProvider.overrideWithValue(companies),
              ],
              child: MaterialApp.router(
                theme: AppTheme.light,
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (pushed) {
            await tester.tap(find.text('Empresas'));
            await tester.pumpAndSettle();
          }
          if (save) {
            await tester.enterText(find.byType(TextField).first, 'Empresa teste');
            await tester.tap(find.text('Criar empresa'));
            await tester.pumpAndSettle();
            expect(companies.names, ['Empresa teste']);
          } else {
            await tester.tap(find.byTooltip('Voltar'));
            await tester.pumpAndSettle();
            expect(companies.names, isEmpty);
          }
          expect(find.text('Empresas'), findsOneWidget);
          expect(router.canPop(), isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
