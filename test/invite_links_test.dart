import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/features/auth/onboarding_screens.dart';
import 'package:educador/features/auth/pending_invites.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Invitations extends InvitationRepository {
  final PendingInvitation invitation;

  _Invitations({
    this.invitation = const PendingInvitation(
      name: 'Pessoa Convidada',
      email: 'person@example.test',
      role: Role.empresa,
      companyId: 'b0000000-0000-4000-8000-000000000001',
    ),
  });
  int regenerateCalls = 0;

  @override
  Future<List<PendingInvitation>> pending({
    Role? role,
    String? companyId,
  }) async => [invitation];

  @override
  Future<String> regenerate(PendingInvitation invite) async {
    expect(invite, same(invitation));
    regenerateCalls++;
    return 'https://example.test/one-time-link';
  }
}

void main() {
  testWidgets('closing the link warns before discarding it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showInviteLink(context, 'https://example.test/link'),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fechar sem copiar'));
    await tester.pumpAndSettle();
    expect(find.text('Fechar sem copiar?'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('Convite criado'), findsOneWidget);
    await tester.tap(find.text('Fechar sem copiar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fechar sem copiar').last);
    await tester.pumpAndSettle();
    expect(find.text('Convite criado'), findsNothing);
  });

  testWidgets('pending invitation can generate a replacement link', (
    tester,
  ) async {
    final repo = _Invitations();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<dynamic, dynamic>)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [invitationRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: Scaffold(
            body: PendingInvitesSection(
              role: Role.empresa,
              companyId: 'b0000000-0000-4000-8000-000000000001',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('person@example.test'), findsOneWidget);
    expect(find.text('Pessoa Convidada'), findsOneWidget);
    expect(find.text('PC'), findsOneWidget);
    await tester.tap(find.text('Gerar novo link'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('O link anterior deixará de funcionar'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.regenerateCalls, 0);
    await tester.tap(find.text('Gerar novo link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar novo link').last);
    await tester.pumpAndSettle();
    expect(repo.regenerateCalls, 1);
    expect(find.text('Convite criado'), findsOneWidget);
    await tester.tap(find.text('Copiar link'));
    await tester.pumpAndSettle();
    expect(copied, 'https://example.test/one-time-link');
    expect(find.text('Convite criado'), findsNothing);
  });

  for (final width in [320.0, 900.0]) {
    testWidgets('invite identity and action fit at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Invitations(
        invitation: const PendingInvitation(
          name: 'Pessoa Convidada com Nome Comprido',
          email: 'pessoa.com.email.comprido@example.test',
          role: Role.empresa,
          companyId: 'company',
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [invitationRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: PendingInvitesSection(
                  role: Role.empresa,
                  companyNames: {'company': 'Santa Maria com Nome Comprido'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(repo.invitation.name!), findsOneWidget);
      expect(find.text(repo.invitation.email), findsOneWidget);
      expect(find.text('Santa Maria com Nome Comprido'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Gerar novo link'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invites without a name fall back to email', (tester) async {
    final repo = _Invitations(
      invitation: const PendingInvitation(
        name: '  ',
        email: 'person@example.test',
        role: Role.empresa,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [invitationRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: Scaffold(body: PendingInvitesSection(role: Role.empresa)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('person@example.test'), findsOneWidget);
    expect(find.text('P'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
