import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/common.dart';

class CompanyCompletionScreen extends ConsumerWidget {
  const CompanyCompletionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(sessionProvider).value?.active;
    final companyId = company?.companyId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conclusão da empresa'),
        automaticallyImplyLeading: false,
      ),
      body: companyId == null
          ? const Center(child: Text('Selecione uma empresa.'))
          : FutureBuilder<double?>(
              future: ref.read(reportRepositoryProvider).completion(companyId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Não foi possível carregar a conclusão.'),
                  );
                }
                if (!snapshot.hasData &&
                    snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final percent = snapshot.data;
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      company!.companyName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Conclusão dos treinamentos',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            percent == null
                                ? 'Nenhuma trilha liberada'
                                : '${percent.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ProgressBar((percent ?? 0) / 100),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => context.go('/empresa/funcionarios'),
                      child: const Text('Ver conclusão por funcionário'),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
