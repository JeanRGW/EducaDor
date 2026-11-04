import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/security/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth extends AuthRepository {
  bool verified = false;
  bool removed = false;
  @override
  Future<List<String>> totpFactors() async => verified ? ['factor'] : [];
  @override
  Future<({String id, String secret, String qr})> enrollTotp() async => (
    id: 'factor',
    secret: 'TESTSECRET',
    qr: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>',
  );
  @override
  Future<void> removeTotp(String id) async {
    removed = true;
  }
}

void main() {
  testWidgets('setup shows manual key and cancel removes unfinished factor', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: SecuritySettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Desativada.'), findsOneWidget);
    await tester.tap(find.text('Ativar'));
    await tester.pumpAndSettle();
    expect(find.text('TESTSECRET'), findsOneWidget);
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(auth.removed, isTrue);
    expect(find.text('TESTSECRET'), findsNothing);
  });
}
