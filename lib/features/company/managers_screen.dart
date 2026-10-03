import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/admin_styles.dart';
import '../auth/pending_invites.dart';
import '../gestor/management_widgets.dart' show leaveManagementPage;
import '../gestor/widgets.dart' show DataSkeleton;
import 'widgets.dart';

class CompanyManagersScreen extends ConsumerStatefulWidget {
  const CompanyManagersScreen({super.key});

  @override
  ConsumerState<CompanyManagersScreen> createState() =>
      _CompanyManagersScreenState();
}

class _CompanyManagersScreenState extends ConsumerState<CompanyManagersScreen> {
  late Future<List<User>> _people;
  int _pendingRevision = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final companyId = ref.read(sessionProvider).value!.active!.companyId!;
    _people = ref.read(peopleRepositoryProvider).companyManagers(companyId);
    _pendingRevision++;
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: CompanyStyles.theme(Theme.of(context)),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Gestores da empresa'),
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: () => leaveManagementPage(context, '/empresa/perfil'),
          icon: const SvgIcon(
            AppIcons.arrowBack,
            size: 20,
            color: AppColors.successDarkGreen,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Convidar gestor da empresa',
        backgroundColor: AppColors.successDarkGreen,
        shape: const CircleBorder(
          side: BorderSide(color: Colors.white, width: 2),
        ),
        onPressed: () async {
          await context.push('/empresa/manager/add');
          if (mounted) setState(_refresh);
        },
        child: const SvgIcon(AppIcons.plus, color: Colors.white),
      ),
      body: FutureBuilder<List<User>>(
        future: _people,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: CompanyErrorCard(
                message: 'Não foi possível carregar gestores.',
                retry: () => setState(_refresh),
              ),
            );
          }
          if (!snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                DataSkeleton(),
                SizedBox(height: 12),
                DataSkeleton(),
              ],
            );
          }
          final members = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Gestores ativos', style: AdminStyles.cardTitle),
              ),
              if (members.isEmpty)
                const Text(
                  'Nenhum gestor encontrado.',
                  style: AdminStyles.body,
                ),
              for (final member in members) ...[
                AppCard(
                  child: Row(
                    children: [
                      CompanyAvatar(initials: member.initials, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(member.fullName, style: AdminStyles.cardTitle),
                            Text(member.email, style: CompanyStyles.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              PendingInvitesSection(
                key: ValueKey(_pendingRevision),
                role: Role.empresa,
                companyId: ref.read(sessionProvider).value!.active!.companyId!,
              ),
            ],
          );
        },
      ),
    ),
  );
}
