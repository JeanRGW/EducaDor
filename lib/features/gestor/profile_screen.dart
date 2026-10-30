import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/profile.dart';

class GestorProfileScreen extends ConsumerWidget {
  const GestorProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    return ProfilePage(
      initials: session?.user.initials ?? '',
      name: session?.user.fullName ?? 'Gestor',
      subtitle: session?.user.email ?? '',
      badge: 'Gestor da plataforma',
      settings: ProfileAccountSettings(
        editLocation: '/gestor/perfil/edit',
        managementActions: [
          ProfileMenuRow(
            label: 'Configurações da plataforma',
            icon: AppIcons.settings,
            onTap: () => context.push('/gestor/configuracoes'),
          ),
        ],
      ),
    );
  }
}
