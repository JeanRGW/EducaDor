import 'package:educador/app/theme.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/features/company/widgets.dart';
import 'package:educador/features/employee/widgets.dart';
import 'package:educador/shared/widgets/app_icons.dart';
import 'package:educador/shared/widgets/common.dart';
import 'package:educador/shared/widgets/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test(
    'all roles use exact prototype colors rather than generated seed colors',
    () {
      final theme = AppTheme.light;
      expect(theme.colorScheme.primary, const Color(0xFF036FA9));
      expect(theme.colorScheme.secondary, const Color(0xFF0D9488));
      expect(theme.colorScheme.surface, Colors.white);
      expect(theme.colorScheme.onSurface, AppColors.textPrimary);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
      expect(theme.appBarTheme.backgroundColor, Colors.white);
      expect(theme.visualDensity, VisualDensity.standard);
      for (final roleTheme in [
        theme,
        CompanyStyles.theme(theme),
        EmployeeStyles.theme(theme),
      ]) {
        expect(
          roleTheme.filledButtonTheme.style!.backgroundColor!.resolve({}),
          AppColors.primary,
        );
        expect(
          roleTheme.filledButtonTheme.style!.foregroundColor!.resolve({}),
          Colors.white,
        );
        expect(
          roleTheme.textButtonTheme.style!.foregroundColor!.resolve({}),
          AppColors.successDarkGreen,
        );
      }
      expect(
        theme.floatingActionButtonTheme.backgroundColor,
        AppColors.primary,
      );
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
    },
  );

  testWidgets(
    'shared cards and progress retain the prototype surface treatment',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: AppCard(child: ProgressBar(0.25))),
        ),
      );
      final card = find
          .descendant(
            of: find.byType(AppCard),
            matching: find.byType(Container),
          )
          .first;
      final decoration =
          tester.widget<Container>(card).decoration! as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect(decoration.borderRadius, BorderRadius.circular(16));
      expect((decoration.border! as Border).top.color, AppColors.border);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, 0.25);
      expect(progress.valueColor!.value, AppColors.primary);
      expect(progress.backgroundColor, AppColors.chipBg);
    },
  );

  test(
    'role navigation keeps all five destinations and the employee home glyph',
    () {
      for (final role in Role.values) {
        final tabs = tabsForRole(role);
        expect(tabs, hasLength(5));
        expect(tabs.last.label, 'Perfil');
      }
      expect(tabsForRole(Role.funcionario).first.icon, AppIcons.home);
      expect(tabsForRole(Role.funcionario)[3].icon, AppIcons.award);
      expect(tabsForRole(Role.empresa).first.icon, AppIcons.grid);
      expect(tabsForRole(Role.gestor).first.icon, AppIcons.grid);
    },
  );

  for (final role in Role.values) {
    for (final width in [320.0, 402.0, 1000.0]) {
      testWidgets(
        '$role navigation fits $width with large text and still switches tabs',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 874));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final tabs = tabsForRole(role);
          final router = GoRouter(
            initialLocation: '/tab0',
            routes: [
              StatefulShellRoute.indexedStack(
                builder: (_, _, shell) =>
                    RoleShell(navigationShell: shell, tabs: tabs, role: role),
                branches: [
                  for (var i = 0; i < tabs.length; i++)
                    StatefulShellBranch(
                      routes: [
                        GoRoute(
                          path: '/tab$i',
                          builder: (_, _) => Scaffold(body: Text('Section $i')),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.8)),
                child: child!,
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (var i = 0; i < tabs.length; i++) {
            expect(find.text(tabs[i].label).hitTestable(), findsOneWidget);
            await tester.tap(find.text(tabs[i].label));
            await tester.pumpAndSettle();
            expect(find.text('Section $i'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
