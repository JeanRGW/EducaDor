import 'package:educador/app/app.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/security/screens.dart';
import 'package:educador/features/auth/onboarding_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const user = User(
  id: 'id',
  fullName: 'Ana',
  email: 'a@example.test',
  initials: 'A',
);
const access = AccessContext(role: Role.gestor, companyName: 'Plataforma');

class MfaSession extends SessionController {
  @override
  Future<AppSession?> build() async =>
      const AppSession(user: user, contexts: [], needsMfa: true);
  void complete() {
    state = const AsyncData(
      AppSession(user: user, contexts: [access], active: access),
    );
    sessionRefresh.refresh();
  }
}

void main() {
  testWidgets('AAL1 blocks protected and invite routes until challenge', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWith(MfaSession.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EducaDorApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MfaChallengeScreen), findsOneWidget);
    container.read(routerProvider).go('/gestor/home');
    await tester.pumpAndSettle();
    expect(find.byType(MfaChallengeScreen), findsOneWidget);
    container.read(routerProvider).go('/invite/accept?token=${'a' * 64}');
    await tester.pumpAndSettle();
    expect(find.byType(MfaChallengeScreen), findsOneWidget);
    (container.read(sessionProvider.notifier) as MfaSession).complete();
    await tester.pumpAndSettle();
    expect(find.byType(AcceptInviteScreen), findsOneWidget);
  });
}
