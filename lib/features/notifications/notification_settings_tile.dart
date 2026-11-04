import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/notification_controller.dart';
import '../../app/theme.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';

class NotificationSettingsTile extends ConsumerWidget {
  const NotificationSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(notificationControllerProvider);
    final description = switch (status) {
      PushStatus.unsupported => 'Não disponível neste dispositivo.',
      PushStatus.unconfigured => 'Notificações não configuradas.',
      PushStatus.signedOut => 'Entre para configurar notificações.',
      PushStatus.contextRequired =>
        'Selecione um perfil para configurar notificações.',
      PushStatus.loading => 'Atualizando...',
      PushStatus.disabled => 'Desativadas para esta conta.',
      PushStatus.permission => 'Ative para receber atualizações.',
      PushStatus.denied =>
        'Permissão bloqueada. Altere nas configurações do dispositivo ou navegador.',
      PushStatus.enabled => 'Ativadas neste dispositivo.',
      PushStatus.error => 'Não foi possível atualizar. Tente novamente.',
    };
    final canChange =
        status == PushStatus.enabled ||
        status == PushStatus.disabled ||
        status == PushStatus.permission ||
        status == PushStatus.denied ||
        status == PushStatus.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTileTheme.merge(
              minLeadingWidth: 20,
              horizontalTitleGap: 12,
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                secondary: const SvgIcon(
                  AppIcons.bell,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.successDarkGreen,
                inactiveThumbColor: AppColors.textMuted,
                inactiveTrackColor: AppColors.background,
                title: Text(
                  'Notificações',
                  style: AdminStyles.body.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  description,
                  style: AdminStyles.body.copyWith(
                    fontSize: 12,
                    color: status == PushStatus.error
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                ),
                value:
                    status == PushStatus.enabled || status == PushStatus.denied,
                onChanged: !canChange
                    ? null
                    : (value) {
                        final controller = ref.read(
                          notificationControllerProvider.notifier,
                        );
                        if (value) {
                          controller.enable();
                        } else {
                          controller.disable();
                        }
                      },
              ),
            ),
            if (status == PushStatus.error)
              Padding(
                padding: const EdgeInsets.fromLTRB(46, 0, 14, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => ref
                        .read(notificationControllerProvider.notifier)
                        .refresh(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.successDarkGreen,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 40),
                    ),
                    child: const Text('Tentar novamente'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
