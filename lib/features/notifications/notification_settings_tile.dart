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
    final failure = status == PushStatus.error
        ? ref.read(notificationControllerProvider.notifier).lastFailure
        : null;
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
      PushStatus.error => switch (failure?.step) {
        PushStep.token =>
          'Não foi possível registrar as notificações neste navegador.',
        PushStep.tokenRegistration =>
          'Não foi possível vincular este dispositivo à sua conta.',
        PushStep.support =>
          'Não foi possível iniciar as notificações neste dispositivo.',
        PushStep.permission || PushStep.permissionRequest =>
          'Não foi possível verificar a permissão de notificações.',
        PushStep.preferenceRead || PushStep.preferenceUpdate =>
          'Não foi possível atualizar a preferência de notificações.',
        _ => 'Não foi possível atualizar. Tente novamente.',
      },
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
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                secondary: SvgIcon(
                  AppIcons.bell,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                activeThumbColor: Colors.white,
                activeTrackColor: context.successForeground,
                inactiveThumbColor: Theme.of(context).colorScheme.outline,
                inactiveTrackColor: Theme.of(context).scaffoldBackgroundColor,
                title: Text(
                  'Notificações',
                  style: AdminStyles.body(context).copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  description,
                  style: AdminStyles.body(context).copyWith(
                    fontSize: 12,
                    color: status == PushStatus.error
                        ? context.dangerForeground
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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
                      foregroundColor: context.successForeground,
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
