import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/auth/invite_forms.dart';
import 'package:educador/features/gestor/screens.dart';
import 'package:educador/shared/widgets/admin_styles.dart';
import 'package:educador/shared/widgets/app_icons.dart';
import 'package:educador/shared/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends SessionController {
  @override
  Future<AppSession?> build() async => const AppSession(
    user: User(
      id: 'gestor',
      fullName: 'Marina Silva',
      email: 'marina@example.test',
      initials: 'MS',
    ),
    contexts: [
      AccessContext(role: Role.gestor, companyName: 'Plataforma'),
      AccessContext(
        role: Role.empresa,
        companyId: 'own-company',
        companyName: 'Empresa',
      ),
    ],
    active: AccessContext(role: Role.gestor, companyName: 'Plataforma'),
  );
}

class _Invites extends InvitationRepository {
  ({
    Role role,
    String name,
    String email,
    String? companyId,
    Map<String, String>? company,
  })?
  request;

  @override
  Future<List<PendingInvitation>> pending({
    Role? role,
    String? companyId,
  }) async => [];

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
    request = (
      role: role,
      name: name,
      email: email,
      companyId: companyId,
      company: company,
    );
    return 'https://example.test/one-time-link';
  }
}

Future<void> _show(
  WidgetTester tester,
  Widget screen, {
  double textScale = 1,
  _Invites? invites,
  TargetPlatform? platform,
}) async {
  final base = AppTheme.light;
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        invitationRepositoryProvider.overrideWithValue(invites ?? _Invites()),
      ],
      child: MaterialApp(
        theme: base.copyWith(
          platform: platform ?? base.platform,
          visualDensity: platform == null
              ? base.visualDensity
              : VisualDensity.defaultDensityForPlatform(platform),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is FormFieldLabel && widget.label == label,
  ),
  matching: find.byType(TextFormField),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      AppFonts.inter: 'assets/fonts/Inter-Variable.ttf',
      AppFonts.outfit: 'assets/fonts/Outfit-Variable.ttf',
    }.entries) {
      final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });
  testWidgets(
    'profile matches the prototype identity and keeps added controls',
    (tester) async {
      await _show(tester, const GestorProfileScreen());
      final avatar = find.byWidgetPredicate(
        (widget) => widget is Container && widget.constraints?.maxWidth == 72,
      );
      expect(tester.getSize(avatar), const Size(72, 72));
      final decoration =
          tester.widget<Container>(avatar).decoration! as BoxDecoration;
      expect(decoration.color, AppColors.successBg);
      expect(
        (decoration.border! as Border).top.color,
        AppColors.successDarkGreen,
      );
      expect(
        tester.widget<Text>(find.text('Marina Silva')).style,
        AdminStyles.formTitle,
      );
      expect(find.text('SUPER ADMIN'), findsOneWidget);
      expect(find.text('Convidar gestor da plataforma'), findsOneWidget);
      expect(find.text('Nenhum convite pendente.'), findsOneWidget);
      expect(find.text('Trocar perfil'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.text('Configurações de Conta'))
            .style!
            .fontSize,
        14,
      );
      await tester.ensureVisible(find.text('Sair'));
      final logoutIcon = tester.widget<SvgIcon>(
        find.byWidgetPredicate(
          (widget) => widget is SvgIcon && widget.asset == AppIcons.userOff,
        ),
      );
      expect(logoutIcon.color, AppColors.danger);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    testWidgets('forms keep prototype dimensions on $platform', (tester) async {
      await tester.binding.setSurfaceSize(const Size(418, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _show(tester, const AddCompanyScreen(), platform: platform);
      expect(tester.getTopLeft(find.text('Adicionar empresa')).dx, 48);
      expect(tester.getTopLeft(_field('Nome da Empresa')).dx, 20);
      expect(tester.getSize(_field('Nome da Empresa')).height, closeTo(40, 2));
      final save = find.widgetWithText(FilledButton, 'Criar empresa e convite');
      final saveSurface = find.descendant(
        of: save,
        matching: find.byType(Material),
      );
      expect(tester.getSize(saveSurface).height, closeTo(46, 0.1));

      await _show(tester, const AddTrailScreen(), platform: platform);
      expect(tester.getTopLeft(find.text('Adicionar Trilha')).dx, 48);
      final video = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'https://youtu.be/...',
      );
      final author = find.ancestor(
        of: find.text('Marina Silva'),
        matching: find.byType(InkWell),
      );
      final audience = find.ancestor(
        of: find.text('Todas as empresas'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(video).height, closeTo(40, 2));
      expect(
        tester.getSize(author).height,
        closeTo(tester.getSize(video).height, 0.1),
      );
      expect(
        tester.getSize(audience).height,
        closeTo(tester.getSize(video).height, 0.1),
      );
      expect(
        tester.getTopLeft(author).dy,
        closeTo(tester.getTopLeft(video).dy, 0.1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('company form keeps validation and invitation data', (
    tester,
  ) async {
    final repo = _Invites();
    await _show(tester, const AddCompanyScreen(), invites: repo);
    await tester.scrollUntilVisible(
      find.text('Criar empresa e convite'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar empresa e convite'));
    await tester.pumpAndSettle();
    expect(repo.request, isNull);
    expect(
      find.text('Informe empresa, responsável e e-mail válidos.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    for (final (label, value) in [
      ('Nome da Empresa', 'Santa Maria'),
      ('CNPJ', '00.000.000/0001-00'),
      ('Primeiro gestor da empresa', 'Pessoa Responsável'),
      ('E-mail do gestor', 'person@example.test'),
    ]) {
      await tester.scrollUntilVisible(
        _field(label),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(_field(label), value);
    }
    await tester.scrollUntilVisible(
      find.text('Criar empresa e convite'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar empresa e convite'));
    await tester.pumpAndSettle();
    expect(repo.request!.role, Role.empresa);
    expect(repo.request!.name, 'Pessoa Responsável');
    expect(repo.request!.email, 'person@example.test');
    expect(repo.request!.company!['name'], 'Santa Maria');
    expect(repo.request!.company!['cnpj'], '00.000.000/0001-00');
    expect(find.text('Convite criado'), findsOneWidget);
    expect(find.text('Copiar link'), findsOneWidget);
  });

  testWidgets(
    'publishing uses compact fields without enabling deferred content types',
    (tester) async {
      await _show(tester, const AddTrailScreen());
      final form = find.byType(TextFormField).first;
      final theme = Theme.of(tester.element(form));
      expect(theme.appBarTheme.titleTextStyle, AdminStyles.formTitle);
      expect(theme.inputDecorationTheme.hintStyle!.fontSize, 13);
      final border =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(8));
      expect(find.text('Módulos'), findsOneWidget);
      expect(find.text('Vídeo do YouTube'), findsOneWidget);
      await tester.tap(find.text('Áudio'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Disponível em breve. Por enquanto, publique vídeos do YouTube.',
        ),
        findsOneWidget,
      );
      expect(find.text('Vídeo do YouTube'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'company and employee invitations keep their existing presentation',
    (tester) async {
      for (final role in [Role.empresa, Role.funcionario]) {
        await _show(tester, InvitePersonScreen(role: role));
        expect(
          tester
              .widget<FormFieldLabel>(find.byType(FormFieldLabel).first)
              .compact,
          isFalse,
        );
        expect(
          tester.widget<PrimaryButton>(find.byType(PrimaryButton)).compact,
          isFalse,
        );
        expect(
          Theme.of(
            tester.element(_field('Nome completo')),
          ).inputDecorationTheme.hintStyle!.fontSize,
          15,
        );
      }
    },
  );

  for (final role in [Role.gestor, Role.empresa]) {
    testWidgets(
      'styled $role invitation keeps the correct authorization target',
      (tester) async {
        final repo = _Invites();
        await _show(
          tester,
          InvitePersonScreen(
            role: role,
            companyId: role == Role.empresa ? 'target-company' : null,
          ),
          invites: repo,
        );
        expect(
          tester
              .widget<FormFieldLabel>(find.byType(FormFieldLabel).first)
              .compact,
          isTrue,
        );
        expect(
          Theme.of(
            tester.element(_field('Nome completo')),
          ).inputDecorationTheme.hintStyle!.fontSize,
          13,
        );
        await tester.enterText(_field('Nome completo'), 'Pessoa Convidada');
        await tester.enterText(_field('E-mail'), 'person@example.test');
        await tester.tap(find.text('Criar convite'));
        await tester.pumpAndSettle();
        expect(repo.request!.role, role);
        expect(
          repo.request!.companyId,
          role == Role.empresa ? 'target-company' : null,
        );
        expect(repo.request!.company, isNull);
        expect(find.text('Convite criado'), findsOneWidget);
      },
    );
  }

  for (final width in [320.0, 390.0, 1000.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'remaining Gestor screens fit width $width at text scale $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          for (final screen in [
            const GestorProfileScreen(),
            const AddCompanyScreen(),
            const AddPlatformManagerScreen(),
            const AddPlatformCompanyManagerScreen(companyId: 'company'),
            const AddTrailScreen(),
          ]) {
            await _show(tester, screen, textScale: scale);
            expect(
              tester.takeException(),
              isNull,
              reason: '${screen.runtimeType}',
            );
            if (screen is AddTrailScreen) {
              await tester.ensureVisible(find.text('Publicar'));
              expect(tester.takeException(), isNull);
            }
          }
        },
      );
    }
  }
}
