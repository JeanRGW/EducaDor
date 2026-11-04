import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/core/authenticator_launcher.dart';
import 'package:educador/app/theme.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/features/security/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth extends AuthRepository {
  bool verified = false;
  bool removed = false;
  int verificationCalls = 0;
  @override
  Future<List<String>> totpFactors() async => verified ? ['factor'] : [];
  @override
  Future<({String id, String secret, String qr, String uri})>
  enrollTotp() async => (
    id: 'factor',
    secret: 'TESTSECRET',
    qr: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>',
    uri: 'otpauth://totp/EducaDor:test?secret=TESTSECRET&issuer=EducaDor',
  );
  @override
  Future<void> verifyTotp(String id, String code) async {
    verificationCalls++;
    verified = true;
  }

  @override
  Future<void> removeTotp(String id) async {
    removed = true;
  }
}

class FakeLauncher extends AuthenticatorLauncher {
  String? opened;
  bool supported = true;
  @override
  Future<bool> open(String value) async {
    opened = value;
    return supported;
  }
}

class FakeSession extends SessionController {
  @override
  Future<AppSession?> build() async => null;
  @override
  Future<AppSession?> reload() async => null;
}

void main() {
  testWidgets('setup shows manual key and cancel removes unfinished factor', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SecuritySettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Desativada'), findsOneWidget);
    await tester.tap(find.text('Ativar'));
    await tester.pumpAndSettle();
    expect(find.text('TEST SECR ET'), findsOneWidget);
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(auth.removed, isTrue);
    expect(find.text('TEST SECR ET'), findsNothing);
  });

  testWidgets(
    'setup copies the raw key and opens the server-provided authenticator URI',
    (tester) async {
      final launcher = FakeLauncher();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
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
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuth()),
            authenticatorLauncherProvider.overrideWithValue(launcher),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SecuritySettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ativar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copiar chave'));
      await tester.tap(find.text('Copiar chave'));
      await tester.pumpAndSettle();
      expect(copied, 'TESTSECRET');
      expect(find.text('Chave copiada'), findsOneWidget);
      await tester.ensureVisible(find.text('Abrir autenticador'));
      await tester.tap(find.text('Abrir autenticador'));
      await tester.pumpAndSettle();
      expect(
        launcher.opened,
        'otpauth://totp/EducaDor:test?secret=TESTSECRET&issuer=EducaDor',
      );
    },
  );

  testWidgets('unsupported authenticator link keeps manual setup available', (
    tester,
  ) async {
    final launcher = FakeLauncher()..supported = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuth()),
          authenticatorLauncherProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SecuritySettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ativar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Abrir autenticador'));
    await tester.tap(find.text('Abrir autenticador'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Não foi possível abrir um autenticador. Copie a chave ou escaneie o QR code.',
      ),
      findsOneWidget,
    );
    expect(find.text('TEST SECR ET'), findsOneWidget);
  });

  testWidgets('mobile setup wraps the key and confirms only a six-digit code', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          sessionProvider.overrideWith(FakeSession.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SecuritySettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ativar'));
    await tester.pumpAndSettle();
    expect(find.text('Configure o autenticador'), findsOneWidget);
    expect(find.text('Confirme a ativação'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirmar ativação'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirmar ativação'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '12a34567');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '123456',
    );
    await tester.ensureVisible(find.text('Confirmar ativação'));
    await tester.tap(find.text('Confirmar ativação'));
    await tester.pumpAndSettle();
    expect(auth.verificationCalls, 1);
    expect(find.text('Ativada'), findsOneWidget);
    expect(find.text('TEST SECR ET'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'authenticator launcher never opens HTTP links with a setup secret',
    () async {
      final launcher = AuthenticatorLauncher();
      for (final value in [
        'https://example.test/?secret=TESTSECRET',
        'otpauth://hotp/test?secret=TESTSECRET',
        'otpauth://totp/test',
        'not a URI',
      ]) {
        expect(await launcher.open(value), isFalse);
      }
    },
  );
}
