import 'dart:async';

import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/auth/screens.dart';
import 'package:educador/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _signedIn = AppSession(
  user: User(
    id: 'user',
    fullName: 'Ana Silva',
    email: 'ana@example.test',
    initials: 'AS',
  ),
  contexts: [AccessContext(role: Role.gestor, companyName: 'Plataforma')],
  active: AccessContext(role: Role.gestor, companyName: 'Plataforma'),
);

class _Session extends SessionController {
  final completion = Completer<AppSession>();
  String? email;
  String? password;
  int calls = 0;

  @override
  Future<AppSession?> build() async => null;

  @override
  Future<AppSession> login({required String email, required String password}) {
    this.email = email;
    this.password = password;
    calls++;
    return completion.future;
  }
}

Future<GoRouter> _show(
  WidgetTester tester, {
  String location = '/login',
  _Session? session,
  TargetPlatform platform = TargetPlatform.linux,
  double textScale = 1,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: '/login',
        builder: (_, state) =>
            LoginScreen(redirectTo: state.uri.queryParameters['redirect']),
      ),
      GoRoute(
        path: '/recover',
        builder: (_, _) => const RecoverPasswordScreen(),
      ),
      for (final path in ['/gestor/home', '/set-password', '/invite/accept'])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text(path)),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionProvider.overrideWith(() => session ?? _Session())],
      child: MaterialApp.router(
        theme: AppTheme.light.copyWith(
          platform: platform,
          visualDensity: VisualDensity.defaultDensityForPlatform(platform),
        ),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _field(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      AppFonts.inter: 'assets/fonts/Inter-Variable.ttf',
      AppFonts.outfit: 'assets/fonts/Outfit-Variable.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  testWidgets('welcome has one centered action and opens login', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(401, 830));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = await _show(tester, location: '/welcome');

    expect(find.text('Tenho um convite'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    final title = tester.widget<Text>(find.text('BEM-VINDO!'));
    expect(title.style!.fontFamily, AppFonts.outfit);
    expect(title.style!.fontSize, 32);
    expect(tester.getCenter(find.byType(FilledButton)).dx, closeTo(200.5, 0.1));
    expect(tester.getSize(find.byType(FilledButton)).width, 130);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    testWidgets('login matches prototype fields on $platform', (tester) async {
      await tester.binding.setSurfaceSize(const Size(401, 830));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _show(tester, platform: platform);

      final logo = tester.widget<SvgIcon>(
        find.byWidgetPredicate(
          (widget) => widget is SvgIcon && widget.asset == AppIcons.logoColor,
        ),
      );
      expect(logo.color, isNull);
      expect(logo.size, 28);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SvgIcon && widget.asset == AppIcons.logo,
        ),
        findsNothing,
      );
      final photo = find.byType(Image);
      final image = tester.widget<Image>(photo);
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/alongamento_login.jpg',
      );
      expect(image.fit, BoxFit.cover);
      expect(tester.getTopLeft(photo).dy, 56);
      expect(tester.getSize(photo).height, closeTo(220.55, 0.1));
      final email = _field('email@empresa.com');
      final password = _field('Sua senha');
      expect(tester.getTopLeft(email).dx, 28);
      expect(tester.getSize(email).width, 345);
      expect(tester.getSize(email).height, closeTo(46, 1));
      expect(
        tester.getSize(password).height,
        closeTo(tester.getSize(email).height, 1),
      );
      expect(
        tester.widget<TextField>(email).keyboardType,
        TextInputType.emailAddress,
      );
      expect(
        tester.widget<TextField>(email).textInputAction,
        TextInputAction.next,
      );
      expect(
        tester.widget<Text>(find.text('Entrar no EducaDOR')).style!.fontFamily,
        AppFonts.outfit,
      );
      final button = find.widgetWithText(FilledButton, 'ENTRAR');
      expect(
        tester
            .getSize(
              find.descendant(of: button, matching: find.byType(Material)),
            )
            .height,
        46,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('login preserves validation, password visibility and recovery', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(401, 830));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _Session();
    final router = await _show(tester, session: session);

    await tester.tap(find.text('ENTRAR'));
    await tester.pumpAndSettle();
    expect(
      find.text('Preencha e-mail e senha para continuar.'),
      findsOneWidget,
    );
    expect(session.calls, 0);
    expect(tester.widget<TextField>(_field('Sua senha')).obscureText, isTrue);
    await tester.tap(find.byTooltip('Mostrar senha'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field('Sua senha')).obscureText, isFalse);
    await tester.tap(find.byTooltip('Ocultar senha'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field('Sua senha')).obscureText, isTrue);
    await tester.tap(find.text('Esqueci a senha'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/recover');
  });

  for (final redirect in [false, true]) {
    testWidgets(
      'login submits once and preserves invite redirect ($redirect)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(401, 830));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final session = _Session();
        final invite = Uri(
          path: '/invite/accept',
          queryParameters: {'token': 'a' * 64},
        );
        final router = await _show(
          tester,
          session: session,
          location: Uri(
            path: '/login',
            queryParameters: redirect ? {'redirect': invite.toString()} : null,
          ).toString(),
        );
        await tester.enterText(_field('email@empresa.com'), 'ana@example.test');
        await tester.enterText(_field('Sua senha'), 'password');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(session.email, 'ana@example.test');
        expect(session.password, 'password');
        expect(session.calls, 1);
        expect(find.text('Entrando…'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        session.completion.complete(_signedIn);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri,
          redirect ? invite : Uri(path: '/gestor/home'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('login failures keep credentials and allow another attempt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(401, 830));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _Session();
    await _show(tester, session: session);
    await tester.enterText(_field('email@empresa.com'), 'ana@example.test');
    await tester.enterText(_field('Sua senha'), 'password');
    await tester.tap(find.text('ENTRAR'));
    await tester.pump();
    session.completion.completeError(StateError('Sign-in failed'));
    await tester.pumpAndSettle();
    expect(
      find.text('Não foi possível entrar. Verifique e-mail e senha.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(_field('email@empresa.com')).controller!.text,
      'ana@example.test',
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(1440, 900)]) {
    testWidgets('auth screens fit $size with large text and keyboard', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _show(tester, location: '/welcome', textScale: 2);
      await tester.ensureVisible(find.text('Entrar'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.ensureVisible(_field('Sua senha'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Sua senha'), 'password');
      await tester.ensureVisible(find.text('ENTRAR'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
