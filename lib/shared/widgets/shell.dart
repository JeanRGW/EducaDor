import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import 'app_icons.dart';

class TabItem {
  final String label;
  final String icon;

  const TabItem(this.label, this.icon);
}

List<TabItem> tabsForRole(Role role) {
  switch (role) {
    case Role.funcionario:
      return const [
        TabItem('Início', AppIcons.grid),
        TabItem('Módulos', AppIcons.book),
        TabItem('Progresso', AppIcons.reports),
        TabItem('Recompensas', AppIcons.rewards),
        TabItem('Perfil', AppIcons.profile),
      ];
    case Role.empresa:
      return const [
        TabItem('Início', AppIcons.grid),
        TabItem('Funcionários', AppIcons.employees),
        TabItem('Gestores', AppIcons.employees),
        TabItem('Relatórios', AppIcons.reports),
        TabItem('Perfil', AppIcons.profile),
      ];
    case Role.gestor:
      return const [
        TabItem('Início', AppIcons.grid),
        TabItem('Empresas', AppIcons.companies),
        TabItem('Conteúdo', AppIcons.book),
        TabItem('Relatórios', AppIcons.reports),
        TabItem('Perfil', AppIcons.profile),
      ];
  }
}

class RoleShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final List<TabItem> tabs;

  const RoleShell({
    super.key,
    required this.navigationShell,
    required this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _TabButton(
                      item: tabs[i],
                      selected: navigationShell.currentIndex == i,
                      onTap: () => navigationShell.goBranch(
                        i,
                        initialLocation: i == navigationShell.currentIndex,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final TabItem item;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgIcon(
            item.icon,
            color: selected ? AppColors.successDarkGreen : AppColors.textMuted,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? AppColors.successDarkGreen
                  : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
