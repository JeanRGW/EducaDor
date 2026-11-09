import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/models.dart';
import '../data/session/session_controller.dart';
import '../shared/widgets/shell.dart';
import '../shared/widgets/route_error_screen.dart';

import '../features/auth/screens.dart';
import '../features/auth/onboarding_screens.dart';
import '../features/auth/invite_forms.dart';
import '../features/employee/screens.dart';
import '../features/employee/player_screen.dart';
import '../features/company/screens.dart';
import '../features/company/managers_screen.dart';
import '../features/company/completion_screen.dart';
import '../features/gestor/screens.dart';
import '../features/gestor/company_detail_screen.dart';
import '../features/gestor/managers_screen.dart';
import '../features/gestor/profile_edit_screen.dart';
import '../features/gestor/platform_settings_screen.dart';
import '../features/content/course_edit_screen.dart';
import '../features/security/screens.dart';
import '../features/auth/recovery_screens.dart';
import 'recovery_link.dart';

const _authRoutes = ['/splash', '/welcome', '/login', '/recover'];

String? _inviteRedirect(String? candidate) {
  if (candidate == null) return null;
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.path != '/invite/accept' ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(uri.queryParameters['token'] ?? '')) {
    return null;
  }
  return uri.toString();
}

final routerProvider = Provider<GoRouter>((ref) {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  String? pendingLocation;
  String? pendingInvite;
  ref.listen(sessionProvider, (_, _) => sessionRefresh.refresh());
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: sessionRefresh,
    debugLogDiagnostics: false,
    errorBuilder: (_, _) => const RouteErrorScreen(),
    redirect: (context, state) {
      final sessionState = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      if (loc == '/recover' || loc == '/recover/complete') return null;
      final isAuth = _authRoutes.contains(loc);
      final protected =
          loc.startsWith('/funcionario/') ||
          loc.startsWith('/empresa/') ||
          loc.startsWith('/gestor/');
      if (protected &&
          (sessionState.isLoading || sessionState.value?.active == null)) {
        pendingLocation = state.uri.toString();
      }
      if (sessionState.isLoading) {
        return loc == '/splash' ||
                loc == '/invite/accept' ||
                loc == '/set-password' ||
                loc == '/reset-password'
            ? null
            : '/splash';
      }
      if (sessionState.hasError) {
        return loc == '/session-error' ? null : '/session-error';
      }
      final session = sessionState.value;

      if (session == null) {
        if (isAuth ||
            loc == '/invite/accept' ||
            loc == '/set-password' ||
            loc == '/reset-password') {
          return null;
        }
        return '/login';
      }
      if (session.needsMfa) {
        if (loc == '/invite/accept') {
          pendingInvite = _inviteRedirect(state.uri.toString());
        }
        if (loc == '/login') {
          pendingInvite =
              _inviteRedirect(state.uri.queryParameters['redirect']) ??
              pendingInvite;
        }
        return loc == '/mfa' ? null : '/mfa';
      }
      if (session.recoveringPassword) {
        return loc == '/reset-password' ? null : '/reset-password';
      }
      if (loc == '/reset-password') return '/recover';
      if (loc == '/mfa') {
        final invite = pendingInvite;
        if (invite != null) return invite;
        return session.needsPassword ? '/set-password' : session.homePath;
      }
      if (loc == '/login') {
        final invite = _inviteRedirect(state.uri.queryParameters['redirect']);
        if (invite != null) return invite;
      }
      if (loc == '/invite/accept') return null;
      pendingInvite = null;
      if (session.needsPassword) {
        return loc == '/set-password' ? null : '/set-password';
      }
      if (loc == '/set-password' || loc == '/contexts') return null;
      if (session.active == null) return '/contexts';
      if (loc == '/account/security') return null;
      if (pendingLocation case final destination?) {
        if (destination.startsWith('/${session.role!.name}/')) {
          pendingLocation = null;
          if (loc != Uri.parse(destination).path) return destination;
        } else {
          pendingLocation = null;
        }
      }
      if (isAuth) return session.homePath;
      if (!loc.startsWith('/${session.role!.name}/')) return session.homePath;
      return null;
    },
    routes: [
      GoRoute(path: '/mfa', builder: (_, _) => const MfaChallengeScreen()),
      GoRoute(
        path: '/account/security',
        builder: (_, _) => const SecuritySettingsScreen(),
      ),
      // ---- Auth ----
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            LoginScreen(redirectTo: state.uri.queryParameters['redirect']),
      ),
      GoRoute(
        path: '/recover',
        builder: (_, _) => const RecoverPasswordScreen(),
      ),
      GoRoute(
        path: '/recover/complete',
        builder: (_, state) =>
            RecoveryLinkScreen(tokenHash: recoveryTokenFromUri(state.uri)),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/contexts',
        builder: (_, _) => const ContextSelectionScreen(),
      ),
      GoRoute(
        path: '/set-password',
        builder: (_, _) => const SetPasswordScreen(),
      ),
      GoRoute(
        path: '/session-error',
        builder: (_, _) => const SessionErrorScreen(),
      ),
      GoRoute(
        path: '/invite/accept',
        builder: (_, state) =>
            AcceptInviteScreen(token: state.uri.queryParameters['token'] ?? ''),
      ),

      // ---- Funcionário (employee) ----
      GoRoute(
        path: '/funcionario/perfil/edit',
        builder: (_, _) =>
            const ProfileEditScreen(fallbackLocation: '/funcionario/perfil'),
      ),
      GoRoute(
        path: '/funcionario/course/:id/lesson/:lessonId',
        builder: (_, state) => EmployeePlayerScreen(
          courseId: state.pathParameters['id']!,
          lessonId: state.pathParameters['lessonId']!,
        ),
      ),
      GoRoute(
        path: '/funcionario/course/:id',
        builder: (context, state) =>
            CourseDetailScreen(courseId: state.pathParameters['id']!),
      ),
      _shell(Role.funcionario, [
        _branch('/funcionario/home', (_) => const EmployeeHomeScreen()),
        _branch('/funcionario/modulos', (_) => const ModulesScreen()),
        _branch(
          '/funcionario/progresso',
          (_) => const EmployeeProgressScreen(),
        ),
        _branch('/funcionario/recompensas', (_) => const RewardsScreen()),
        _branch('/funcionario/perfil', (_) => const EmployeeProfileScreen()),
      ]),

      // ---- Empresa (company admin) ----
      GoRoute(
        path: '/empresa/perfil/edit',
        builder: (_, _) =>
            const ProfileEditScreen(fallbackLocation: '/empresa/perfil'),
      ),
      GoRoute(
        path: '/empresa/employee/add',
        builder: (_, _) => const AddEmployeeScreen(),
      ),
      GoRoute(
        path: '/empresa/manager/add',
        builder: (_, _) => const AddCompanyManagerScreen(),
      ),
      GoRoute(
        path: '/empresa/gestores',
        builder: (_, _) => const CompanyManagersScreen(),
      ),
      _shell(Role.empresa, [
        _branch('/empresa/home', (_) => const CompanyDashboardScreen()),
        _branch('/empresa/funcionarios', (_) => const EmployeesScreen()),
        _branch('/empresa/conteudo', (_) => const CompanyContentScreen()),
        _branch('/empresa/relatorios', (_) => const CompanyCompletionScreen()),
        _branch('/empresa/perfil', (_) => const CompanyProfileScreen()),
      ]),

      // ---- Gestor (super admin) ----
      GoRoute(
        path: '/gestor/configuracoes',
        builder: (_, _) => const PlatformSettingsScreen(),
      ),
      GoRoute(
        path: '/gestor/gestores',
        builder: (_, _) => const GestorManagersScreen(),
      ),
      GoRoute(
        path: '/gestor/perfil/edit',
        builder: (_, _) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: '/gestor/course/:id',
        builder: (_, state) =>
            CourseEditScreen(courseId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/gestor/company/:id/gestores',
        builder: (_, state) =>
            GestorManagersScreen(companyId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/gestor/company/add',
        builder: (_, _) => const AddCompanyScreen(),
      ),
      GoRoute(
        path: '/gestor/company/:id/manager/add',
        builder: (_, state) => AddPlatformCompanyManagerScreen(
          companyId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/gestor/manager/add',
        builder: (_, _) => const AddPlatformManagerScreen(),
      ),
      GoRoute(
        path: '/gestor/trail/add',
        builder: (_, _) => const AddTrailScreen(),
      ),
      GoRoute(
        path: '/gestor/company/:id',
        builder: (_, state) =>
            CompanyDetailScreen(companyId: state.pathParameters['id']!),
      ),
      _shell(Role.gestor, [
        _branch('/gestor/home', (_) => const GestorDashboardScreen()),
        _branch('/gestor/empresas', (_) => const CompaniesScreen()),
        _branch('/gestor/conteudo', (_) => const ContentManagementScreen()),
        _branch('/gestor/relatorios', (_) => const GestorReportsScreen()),
        _branch('/gestor/perfil', (_) => const GestorProfileScreen()),
      ]),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(String path, WidgetBuilder builder) =>
    StatefulShellBranch(
      routes: [
        GoRoute(path: path, builder: (context, state) => builder(context)),
      ],
    );

StatefulShellRoute _shell(Role role, List<StatefulShellBranch> branches) {
  return StatefulShellRoute.indexedStack(
    builder: (context, state, shell) =>
        RoleShell(navigationShell: shell, tabs: tabsForRole(role), role: role),
    branches: branches,
  );
}
