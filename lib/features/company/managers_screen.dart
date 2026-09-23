import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';

class CompanyManagersScreen extends ConsumerStatefulWidget {
  const CompanyManagersScreen({super.key});

  @override
  ConsumerState<CompanyManagersScreen> createState() =>
      _CompanyManagersScreenState();
}

class _CompanyManagersScreenState extends ConsumerState<CompanyManagersScreen> {
  late Future<(List<User>, List<String>)> _people;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final companyId = ref.read(sessionProvider).value!.active!.companyId!;
    final repo = ref.read(peopleRepositoryProvider);
    _people = (Future.wait<dynamic>([
      repo.companyManagers(companyId),
      repo.pending('empresa'),
    ])).then((rows) => (rows[0] as List<User>, rows[1] as List<String>));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Gestores da empresa'),
      automaticallyImplyLeading: false,
    ),
    floatingActionButton: FloatingActionButton(
      tooltip: 'Convidar gestor da empresa',
      onPressed: () async {
        await context.push('/empresa/manager/add');
        if (mounted) setState(_refresh);
      },
        child: const SvgIcon(AppIcons.plus, color: Colors.white),
    ),
    body: FutureBuilder<(List<User>, List<String>)>(
      future: _people,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Não foi possível carregar gestores.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (members, pending) = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader('Gestores ativos'),
            for (final member in members) ...[
              AppCard(
                child: Row(
                  children: [
                    AvatarBadge(member.initials, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            member.email,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SectionHeader('Convites pendentes'),
            if (pending.isEmpty) const Text('Nenhum convite pendente.'),
            for (final email in pending) AppCard(child: Text(email)),
          ],
        );
      },
    ),
  );
}
