import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/models.dart';
import '../data/session/session_controller.dart';
import '../shared/widgets/shell.dart';

import '../features/auth/screens.dart';
import '../features/auth/onboarding_screens.dart';
import '../features/auth/invite_forms.dart';
import '../features/employee/screens.dart';
import '../features/company/screens.dart';
import '../features/company/managers_screen.dart';
import '../features/company/completion_screen.dart';
import '../features/gestor/screens.dart';

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
  ref.listen(sessionProvider, (_, _) => sessionRefresh.refresh());
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: sessionRefresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final sessionState = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      final isAuth = _authRoutes.contains(loc);
      if (sessionState.isLoading) {
        return loc == '/splash' ||
                loc == '/invite/accept' ||
                loc == '/set-password'
            ? null
            : '/splash';
      }
      if (sessionState.hasError) {
        return loc == '/session-error' ? null : '/session-error';
      }
      final session = sessionState.value;

      if (session == null) {
        if (isAuth || loc == '/invite/accept' || loc == '/set-password') {
          return null;
        }
        return '/login';
      }
      if (loc == '/login') {
        final invite = _inviteRedirect(state.uri.queryParameters['redirect']);
        if (invite != null) return invite;
      }
      if (loc == '/invite/accept') return null;
      if (session.needsPassword) {
        return loc == '/set-password' ? null : '/set-password';
      }
      if (loc == '/set-password' || loc == '/contexts') return null;
      if (session.active == null) return '/contexts';
      if (isAuth) return session.homePath;
      if (!loc.startsWith('/${session.role!.name}/')) return session.homePath;
      return null;
    },
    routes: [
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
        path: '/empresa/employee/add',
        builder: (_, _) => const AddEmployeeScreen(),
      ),
      GoRoute(
        path: '/empresa/manager/add',
        builder: (_, _) => const AddCompanyManagerScreen(),
      ),
      _shell(Role.empresa, [
        _branch('/empresa/home', (_) => const CompanyDashboardScreen()),
        _branch('/empresa/funcionarios', (_) => const EmployeesScreen()),
        _branch('/empresa/gestores', (_) => const CompanyManagersScreen()),
        _branch('/empresa/relatorios', (_) => const CompanyCompletionScreen()),
        _branch('/empresa/perfil', (_) => const CompanyProfileScreen()),
      ]),

      // ---- Gestor (super admin) ----
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
        RoleShell(navigationShell: shell, tabs: tabsForRole(role)),
    branches: branches,
  );
}
