import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/notification_controller.dart';

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
    return Card(
      child: SwitchListTile(
        title: const Text('Notificações'),
        subtitle: Text(description),
        value: status == PushStatus.enabled || status == PushStatus.denied,
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
    );
  }
}
