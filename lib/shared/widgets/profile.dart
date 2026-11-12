import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/theme_preference.dart';
import '../../data/session/session_controller.dart';
import '../../features/notifications/notification_settings_tile.dart';
import 'admin_styles.dart';
import 'app_icons.dart';
import 'common.dart';

class ProfilePage extends StatelessWidget {
  final String initials;
  final String name;
  final String subtitle;
  final String badge;
  final Widget? summary;
  final Widget settings;
  final Future<void> Function()? onRefresh;

  const ProfilePage({
    super.key,
    required this.initials,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.settings,
    this.summary,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672),
              child: Column(
                children: [
                  AvatarBadge(initials, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: AdminStyles.pageTitle(context),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AdminStyles.body(context),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      textAlign: TextAlign.center,
                      style: AdminStyles.fieldLabel(context).copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  if (summary != null) ...[
                    const SizedBox(height: 28),
                    summary!,
                  ],
                ],
              ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: settings,
            ),
          ),
        ),
      ],
    );
    return Theme(
      data: AdminStyles.screenTheme(Theme.of(context)),
      child: Scaffold(
        body: SafeArea(
          child: onRefresh == null
              ? content
              : RefreshIndicator(onRefresh: onRefresh!, child: content),
        ),
      ),
    );
  }
}

class ProfileMenuRow extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback? onTap;
  final String? status;

  const ProfileMenuRow({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.status,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SvgIcon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: AdminStyles.body(context).copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      status!,
                      style: AdminStyles.body(context).copyWith(fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  SvgIcon(
                    AppIcons.chevronRight,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ProfileAccountSettings extends ConsumerStatefulWidget {
  final String editLocation;
  final VoidCallback? onProfileEdited;
  final List<Widget> managementActions;
  final List<Widget> notices;

  const ProfileAccountSettings({
    super.key,
    required this.editLocation,
    this.onProfileEdited,
    this.managementActions = const [],
    this.notices = const [],
  });

  @override
  ConsumerState<ProfileAccountSettings> createState() =>
      _ProfileAccountSettingsState();
}

class _ProfileAccountSettingsState
    extends ConsumerState<ProfileAccountSettings> {
  bool _signingOut = false;

  Future<void> _logout() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(sessionProvider.notifier).logout();
      if (mounted) context.go('/welcome');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível sair. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.notices,
        if (widget.managementActions.isNotEmpty) ...[
          Text('Gestão', style: AdminStyles.cardTitle(context)),
          const SizedBox(height: 12),
          ...widget.managementActions,
          const SizedBox(height: 12),
        ],
        Text('Configurações de conta', style: AdminStyles.cardTitle(context)),
        const SizedBox(height: 12),
        ProfileMenuRow(
          label: 'Editar dados pessoais',
          icon: AppIcons.manageAccount,
          onTap: () async {
            await context.push(widget.editLocation);
            if (mounted) widget.onProfileEdited?.call();
          },
        ),
        const NotificationSettingsTile(),
        const ProfileMenuRow(
          label: 'Idioma',
          icon: AppIcons.globe,
          status: 'Português (Brasil)',
        ),
        SwitchListTile(
          title: const Text('Seguir aparência do sistema'),
          subtitle: const Text('Usa o tema claro ou escuro do seu dispositivo'),
          secondary: const SvgIcon(AppIcons.globe, size: 20),
          value: ref.watch(themePreferenceProvider) == ThemeMode.system,
          onChanged: (enabled) async {
            try {
              await ref
                  .read(themePreferenceProvider.notifier)
                  .setMode(enabled ? ThemeMode.system : ThemeMode.light);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Não foi possível salvar a aparência. Tente novamente.',
                    ),
                  ),
                );
              }
            }
          },
        ),
        SwitchListTile(
          title: const Text('Modo escuro'),
          secondary: const SvgIcon(AppIcons.moon, size: 20),
          value: ref.watch(themePreferenceProvider) == ThemeMode.dark,
          onChanged: ref.watch(themePreferenceProvider) == ThemeMode.system
              ? null
              : (enabled) async {
                  try {
                    await ref
                        .read(themePreferenceProvider.notifier)
                        .setMode(enabled ? ThemeMode.dark : ThemeMode.light);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Não foi possível salvar a aparência. Tente novamente.',
                          ),
                        ),
                      );
                    }
                  }
                },
        ),
        ProfileMenuRow(
          label: 'Segurança e MFA',
          icon: AppIcons.security,
          onTap: () => context.push('/account/security'),
        ),
        const ProfileMenuRow(
          label: 'Suporte e ajuda',
          icon: AppIcons.help,
          status: 'Em breve',
        ),
        if ((session?.contexts.length ?? 0) > 1)
          ProfileMenuRow(
            label: 'Trocar perfil',
            icon: AppIcons.profile,
            onTap: () => context.go('/contexts'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _signingOut ? null : _logout,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            backgroundColor: Theme.of(context).colorScheme.surface,
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.3)),
            minimumSize: const Size.fromHeight(48),
            textStyle: AdminStyles.body(
              context,
            ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          icon: const SvgIcon(
            AppIcons.logout,
            size: 20,
            color: AppColors.danger,
          ),
          label: Text(_signingOut ? 'Saindo...' : 'Sair'),
        ),
      ],
    );
  }
}
