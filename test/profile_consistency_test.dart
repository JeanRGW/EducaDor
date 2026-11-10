import 'package:educador/app/theme.dart';
import 'package:educador/core/router.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/company_providers.dart';
import 'package:educador/data/repositories/employee_providers.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:educador/features/auth/pending_invites.dart';
import 'package:educador/features/gestor/platform_settings_screen.dart';
import 'package:educador/features/gestor/profile_edit_screen.dart';
import 'package:educador/shared/widgets/admin_styles.dart';
import 'package:educador/shared/widgets/app_icons.dart';
import 'package:educador/shared/widgets/common.dart';
import 'package:educador/shared/widgets/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = User(
  id: 'user',
  fullName: 'Jean Rafael Guilouski Wojcik',
  email: 'jean@example.test',
  initials: 'JR',
);
const _contexts = [
  AccessContext(role: Role.gestor, companyName: 'Plataforma'),
  AccessContext(
    role: Role.empresa,
    companyId: 'company',
    companyName: 'Santa Maria',
  ),
  AccessContext(
    role: Role.funcionario,
    companyId: 'company',
    companyName: 'Santa Maria',
  ),
];

class _Session extends SessionController {
  final Role role;
  final bool multiple;
  bool failLogout = false;
  int logoutCalls = 0;
  int reloadCalls = 0;
  Gender? refreshedGender;

  @override
  Future<AppSession?> reload() async {
    reloadCalls++;
    final current = state.value!;
    state = AsyncData(
      AppSession(
        user: User(
          id: _user.id,
          fullName: _user.fullName,
          email: _user.email,
          initials: _user.initials,
          gender: refreshedGender,
        ),
        contexts: current.contexts,
        active: current.active,
      ),
    );
    return state.value;
  }

  _Session(this.role, {this.multiple = true});

  @override
  Future<AppSession?> build() async {
    final active = _contexts.firstWhere((context) => context.role == role);
    return AppSession(
      user: _user,
      contexts: multiple ? _contexts : [active],
      active: active,
    );
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (failLogout) throw StateError('Offline');
    state = const AsyncData(null);
    sessionRefresh.refresh();
  }
}

class _Invites extends InvitationRepository {
  final roles = <Role?>[];
  @override
  Future<List<PendingInvitation>> pending({
    String search = '',
    int offset = 0,
    Role? role,
    String? companyId,
  }) async {
    roles.add(role);
    return [];
  }
}

class _Profiles extends ProfileRepository {
  OwnProfile profile = const OwnProfile(
    fullName: 'Jean Rafael Guilouski Wojcik',
    email: 'jean@example.test',
    phone: '123',
    address: 'Rua A',
    birthDate: '1990-01-01',
    gender: Gender.male,
  );
  final writes = <OwnProfile>[];
  @override
  Future<OwnProfile> own() async => profile;
  @override
  Future<void> update(OwnProfile value) async {
    writes.add(value);
    profile = value;
  }
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  Role role, {
  double width = 390,
  double scale = 1,
  bool multiple = true,
  _Session? session,
  _Invites? invites,
  _Profiles? profiles,
}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(
        () => session ?? _Session(role, multiple: multiple),
      ),
      invitationRepositoryProvider.overrideWithValue(invites ?? _Invites()),
      profileRepositoryProvider.overrideWithValue(profiles ?? _Profiles()),
      companyIdentityProvider.overrideWith(
        (ref) async => const Company(
          id: 'company',
          name: 'Santa Maria',
          cnpj: '12.345.678/0001-90',
          responsibleName: '',
          email: '',
          phone: '',
          address: '',
          city: '',
          state: '',
          field: '',
          employeeCount: 2,
          active: true,
          registeredAt: '',
          initials: 'SM',
        ),
      ),
      companyDashboardProvider.overrideWith(
        (ref) async => const CompanyDashboard(
          employeeCount: 2,
          activeCourseCount: 1,
          certificateCount: 1,
          engagement: [],
          highlights: [],
        ),
      ),
      employeeSummaryProvider.overrideWith(
        (ref) async => const EmployeeSummary(
          courseCount: 2,
          completedCourseCount: 1,
          certificateCount: 1,
          balance: 80,
          department: 'Dev',
          activity: [],
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.future);
  final router = container.read(routerProvider);
  router.go('/${role.name}/perfil');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('profile gender is initialized, saved, cleared and refreshed', (
    tester,
  ) async {
    final profiles = _Profiles();
    final session = _Session(Role.gestor);
    final container = await _show(
      tester,
      Role.gestor,
      session: session,
      profiles: profiles,
    );
    for (final (initial, choice, result) in [
      (Gender.male, 'Feminino', Gender.female),
      (Gender.female, 'Não informado', null),
    ]) {
      container.read(routerProvider).go('/gestor/perfil/edit');
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<Gender?>);
      expect(
        tester.widget<DropdownButtonFormField<Gender?>>(dropdown).initialValue,
        initial,
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
      session.refreshedGender = result;
      await tester.scrollUntilVisible(
        find.text('Salvar perfil'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ProfileEditScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await _tap(tester, 'Salvar perfil');
      final saved = profiles.writes.last;
      expect(saved.gender, result);
      expect(saved.fullName, _user.fullName);
      expect(saved.email, _user.email);
      expect(saved.phone, '123');
      expect(saved.address, 'Rua A');
      expect(saved.birthDate, '1990-01-01');
      expect(container.read(sessionProvider).value!.user.gender, result);
    }
    expect(session.reloadCalls, 2);
  });

  for (final role in Role.values) {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 1.8), (1200.0, 1.0)]) {
      testWidgets(
        '$role profile shares layout at width $width and text scale $scale',
        (tester) async {
          final invites = _Invites();
          await _show(
            tester,
            role,
            width: width,
            scale: scale,
            invites: invites,
          );
          expect(find.byType(ProfilePage), findsOneWidget);
          expect(find.byType(ProfileAccountSettings), findsOneWidget);
          final page = tester.widget<ProfilePage>(find.byType(ProfilePage));
          expect(
            tester.widget<Text>(find.text(page.name)).style,
            AdminStyles.pageTitle,
          );
          expect(tester.getSize(find.byType(AvatarBadge)), const Size(72, 72));
          final settings = find.byType(ProfileAccountSettings);
          expect(tester.getSize(settings).width, lessThanOrEqualTo(688));
          for (final (label, icon, status) in [
            ('Editar dados pessoais', AppIcons.manageAccount, null),
            ('Idioma', AppIcons.globe, 'Português (Brasil)'),
            ('Modo escuro', AppIcons.moon, 'Em breve'),
            ('Segurança e MFA', AppIcons.security, null),
            ('Suporte e ajuda', AppIcons.help, 'Em breve'),
            ('Trocar perfil', AppIcons.profile, null),
          ]) {
            final row = tester.widget<ProfileMenuRow>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(ProfileMenuRow),
              ),
            );
            expect(row.icon, icon);
            expect(row.status, status);
            expect(row.onTap == null, status != null);
            expect(tester.widget<Text>(find.text(label)).style?.fontSize, 14);
          }
          expect(find.text('Convidar gestor da plataforma'), findsNothing);
          expect(find.byType(PendingInvitesSection), findsNothing);
          expect(invites.roles, isEmpty);
          expect(
            find.text('Configurações da plataforma'),
            role == Role.gestor ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Gestores da empresa'),
            role == Role.empresa ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Concluídos'),
            role == Role.funcionario ? findsOneWidget : findsNothing,
          );
          await tester.ensureVisible(find.text('Sair'));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$role personal editor opens and returns to its profile', (
      tester,
    ) async {
      final container = await _show(tester, role);
      await _tap(tester, 'Editar dados pessoais');
      expect(find.byType(ProfileEditScreen), findsOneWidget);
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/${role.name}/perfil/edit',
      );
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$role hides context switching with only one context', (
      tester,
    ) async {
      await _show(tester, role, multiple: false);
      expect(find.text('Trocar perfil'), findsNothing);
    });
  }

  testWidgets(
    'platform invitations live in settings and refresh after returning from invite',
    (tester) async {
      final invites = _Invites();
      final container = await _show(tester, Role.gestor, invites: invites);
      await _tap(tester, 'Configurações da plataforma');
      expect(find.byType(PlatformSettingsScreen), findsOneWidget);
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/gestor/configuracoes',
      );
      expect(find.text('Convidar gestor da plataforma'), findsOneWidget);
      expect(find.text('Gerenciar gestores da plataforma'), findsOneWidget);
      expect(find.text('Convites pendentes'), findsOneWidget);
      expect(invites.roles, [Role.gestor]);
      await _tap(tester, 'Convidar gestor da plataforma');
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/gestor/manager/add',
      );
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(PlatformSettingsScreen), findsOneWidget);
      expect(invites.roles, [Role.gestor, Role.gestor]);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('Convites pendentes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared sign-out reports failure and allows retry', (
    tester,
  ) async {
    final session = _Session(Role.gestor)..failLogout = true;
    final container = await _show(tester, Role.gestor, session: session);
    await _tap(tester, 'Sair');
    expect(session.logoutCalls, 1);
    expect(
      find.text('Não foi possível sair. Tente novamente.'),
      findsOneWidget,
    );
    expect(find.text('Sair'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    session.failLogout = false;
    await _tap(tester, 'Sair');
    expect(session.logoutCalls, 2);
    expect(container.read(sessionProvider).value, isNull);
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/welcome',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform settings remain usable with large text on mobile', (
    tester,
  ) async {
    await _show(tester, Role.gestor, width: 320, scale: 1.8);
    await _tap(tester, 'Configurações da plataforma');
    expect(find.byType(PlatformSettingsScreen), findsOneWidget);
    await tester.ensureVisible(find.text('Gerenciar gestores da plataforma'));
    expect(tester.takeException(), isNull);
    await _tap(tester, 'Gerenciar gestores da plataforma');
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.byType(PlatformSettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final role in [Role.empresa, Role.funcionario]) {
    testWidgets('$role cannot enter platform settings by URL', (tester) async {
      final invites = _Invites();
      final container = await _show(tester, role, invites: invites);
      final router = container.read(routerProvider);
      router.go('/gestor/configuracoes');
      await tester.pumpAndSettle();
      expect(find.byType(PlatformSettingsScreen), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/${role.name}/home',
      );
      expect(invites.roles, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
