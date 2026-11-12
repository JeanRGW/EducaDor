import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/models.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/profile.dart';
import '../auth/pending_invites.dart';
import 'management_widgets.dart';

class PlatformSettingsScreen extends ConsumerStatefulWidget {
  const PlatformSettingsScreen({super.key});

  @override
  ConsumerState<PlatformSettingsScreen> createState() =>
      _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState
    extends ConsumerState<PlatformSettingsScreen> {
  int _pendingRevision = 0;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionProvider).value?.user.id;
    return ManagementPage(
      title: 'Configurações da plataforma',
      fallbackLocation: '/gestor/perfil',
      child: RefreshIndicator(
        onRefresh: () async => setState(() => _pendingRevision++),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Gestores da plataforma',
              style: AdminStyles.cardTitle(context),
            ),
            const SizedBox(height: 8),
            Text(
              'Gerencie os acessos de quem administra a plataforma.',
              style: AdminStyles.body(context),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              'Convidar gestor da plataforma',
              compact: true,
              onPressed: () async {
                await context.push('/gestor/manager/add');
                if (mounted) setState(() => _pendingRevision++);
              },
            ),
            const SizedBox(height: 12),
            ProfileMenuRow(
              label: 'Gerenciar gestores da plataforma',
              icon: AppIcons.groups,
              onTap: () async {
                await context.push('/gestor/gestores');
                if (mounted) setState(() => _pendingRevision++);
              },
            ),
            const SizedBox(height: 12),
            PendingInvitesSection(
              key: ValueKey((_pendingRevision, userId)),
              role: Role.gestor,
            ),
          ],
        ),
      ),
    );
  }
}
