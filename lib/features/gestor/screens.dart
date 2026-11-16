import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/common.dart';
import '../content/catalog_screen.dart';
import '../content/publish_video_screen.dart';
import 'management_widgets.dart';

export 'companies_screen.dart';
export 'dashboard_screen.dart';
export 'reports_screen.dart';
export 'profile_screen.dart';

class ContentManagementScreen extends StatelessWidget {
  const ContentManagementScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const ContentCatalogScreen(platform: true);
}

class AddTrailScreen extends StatelessWidget {
  const AddTrailScreen({super.key});
  @override
  Widget build(BuildContext context) => const PublishVideoScreen();
}

class AddCompanyScreen extends ConsumerStatefulWidget {
  const AddCompanyScreen({super.key});
  @override
  ConsumerState<AddCompanyScreen> createState() => _AddCompanyScreenState();
}

class _AddCompanyScreenState extends ConsumerState<AddCompanyScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome da empresa.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(companyRepositoryProvider)
          .create(name: _name.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Empresa criada. Abra a empresa para convidar o primeiro gestor '
            'e completar os dados.',
          ),
        ),
      );
      leaveManagementPage(context, '/gestor/empresas');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível criar a empresa.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AdminStyles.formTheme(Theme.of(context)),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar empresa'),
        leading: IconButton(
          tooltip: 'Voltar',
          icon: SvgIcon(
            AppIcons.arrowBack,
            size: 20,
            color: context.successForeground,
          ),
          onPressed: () => leaveManagementPage(context, '/gestor/empresas'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          FormFieldLabel(
            label: 'Nome da Empresa',
            compact: true,
            hint: 'santa maria',
            controller: _name,
          ),
          const SizedBox(height: 12),
          Text(
            'O primeiro gestor é convidado depois, na página da empresa. '
            'Os demais dados podem ser preenchidos quando ela quiser.',
            style: AdminStyles.body(context).copyWith(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            _busy ? 'Criando...' : 'Criar empresa',
            compact: true,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    ),
  );
}
