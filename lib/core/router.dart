import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/models.dart';
import '../data/session/session_controller.dart';
import '../shared/widgets/shell.dart';

import '../features/auth/screens.dart';
import '../features/employee/screens.dart';
import '../features/company/screens.dart';
import '../features/gestor/screens.dart';

const _authRoutes = [
  '/splash',
  '/welcome',
  '/role-select',
  '/login',
  '/recover',
];

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: sessionRefresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      final isAuth = _authRoutes.contains(loc);

      if (session == null) {
        if (isAuth) return null;
        return '/welcome';
      }
      if (isAuth || loc == '/splash') return session.homePath;
      return null;
    },
    routes: [
      // ---- Auth ----
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
          path: '/role-select', builder: (_, _) => const RoleSelectScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            LoginScreen(initialRole: state.extra as Role?),
      ),
      GoRoute(
          path: '/recover', builder: (_, _) => const RecoverPasswordScreen()),

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
            '/funcionario/progresso', (_) => const EmployeeProgressScreen()),
        _branch('/funcionario/recompensas', (_) => const RewardsScreen()),
        _branch('/funcionario/perfil', (_) => const EmployeeProfileScreen()),
      ]),

      // ---- Empresa (company admin) ----
      GoRoute(
        path: '/empresa/employee/add',
        builder: (_, _) => const AddEmployeeScreen(),
      ),
      _shell(Role.empresa, [
        _branch('/empresa/home', (_) => const CompanyDashboardScreen()),
        _branch('/empresa/funcionarios', (_) => const EmployeesScreen()),
        _branch('/empresa/conteudo', (_) => const CompanyContentScreen()),
        _branch('/empresa/relatorios', (_) => const ReportsScreen()),
        _branch('/empresa/perfil', (_) => const CompanyProfileScreen()),
      ]),

      // ---- Gestor (super admin) ----
      GoRoute(
        path: '/gestor/company/add',
        builder: (_, _) => const AddCompanyScreen(),
      ),
      GoRoute(path: '/gestor/trail/add', builder: (_, _) => const AddTrailScreen()),
      _shell(Role.gestor, [
        _branch('/gestor/home', (_) => const GestorDashboardScreen()),
        _branch('/gestor/empresas', (_) => const CompaniesScreen()),
        _branch('/gestor/conteudo', (_) => const ContentManagementScreen()),
        _branch('/gestor/relatorios', (_) => const GestorReportsScreen()),
        _branch('/gestor/perfil', (_) => const GestorProfileScreen()),
      ]),
    ],
  );
});

StatefulShellBranch _branch(String path, WidgetBuilder builder) =>
    StatefulShellBranch(
        routes: [
          GoRoute(path: path, builder: (context, state) => builder(context))
        ]);

StatefulShellRoute _shell(Role role, List<StatefulShellBranch> branches) {
  return StatefulShellRoute.indexedStack(
    builder: (context, state, shell) =>
        RoleShell(navigationShell: shell, tabs: tabsForRole(role)),
    branches: branches,
  );
}
