import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/gestor/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Invites extends InvitationRepository {
  int calls = 0;
  @override
  Future<String> invite({
    required Role role,
    required String name,
    required String email,
    String? companyId,
    Map<String, String>? company,
    String? department,
    String? jobTitle,
  }) async {
    calls++;
    return 'https://example.test/invite';
  }
}

void main() {
  for (final pushed in [false, true]) {
    for (final save in [false, true]) {
      testWidgets(
        'add company ${save ? 'success' : 'back'} navigates safely (pushed: $pushed)',
        (tester) async {
          final invites = _Invites();
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
              GoRoute(
                path: '/add',
                builder: (_, _) => const AddCompanyScreen(),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                invitationRepositoryProvider.overrideWithValue(invites),
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
            final fields = find.byType(TextField);
            await tester.enterText(fields.at(0), 'Empresa teste');
            await tester.enterText(fields.at(2), 'Responsável');
            await tester.enterText(fields.at(3), 'gestor@example.test');
            await tester.scrollUntilVisible(
              find.text('Criar empresa e convite'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text('Criar empresa e convite'));
            await tester.pumpAndSettle();
            expect(find.text('Convite criado'), findsOneWidget);
            await tester.tap(find.text('Fechar sem copiar'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.widgetWithText(FilledButton, 'Fechar sem copiar'),
            );
            await tester.pumpAndSettle();
            expect(invites.calls, 1);
          } else {
            await tester.tap(find.byTooltip('Voltar'));
            await tester.pumpAndSettle();
          }
          expect(find.text('Empresas'), findsOneWidget);
          expect(router.canPop(), isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
