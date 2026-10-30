import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/admin_styles.dart';
import '../gestor/management_widgets.dart';

String? youtubeVideoId(String input) {
  final value = input.trim();
  final valid = RegExp(r'^[A-Za-z0-9_-]{11}$');
  if (valid.hasMatch(value)) return value;
  final uri = Uri.tryParse(value);
  if (uri == null || !['https', 'http'].contains(uri.scheme)) return null;
  String? id;
  if (uri.host == 'youtu.be') {
    id = uri.pathSegments.firstOrNull;
  } else if ([
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
  ].contains(uri.host)) {
    if (uri.path == '/watch') id = uri.queryParameters['v'];
    if (uri.pathSegments.length == 2 &&
        ['embed', 'shorts', 'live'].contains(uri.pathSegments.first)) {
      id = uri.pathSegments.last;
    }
  }
  return id != null && valid.hasMatch(id) ? id : null;
}

class PublishVideoScreen extends ConsumerStatefulWidget {
  const PublishVideoScreen({super.key});
  @override
  ConsumerState<PublishVideoScreen> createState() => _CreateCourseState();
}

class _CreateCourseState extends ConsumerState<PublishVideoScreen> {
  final _title = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(contentRepositoryProvider)
          .createCourse(_title.text);
      if (!mounted) return;
      context.pushReplacement('/gestor/course/$id');
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível criar o curso. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: 'Adicionar curso',
    fallbackLocation: '/gestor/conteudo',
    busy: _busy,
    child: Theme(
      data: AdminStyles.formTheme(Theme.of(context)),
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Curso → Módulos → Aulas'),
            const SizedBox(height: 16),
            const Text(
              'Crie o curso, organize seus módulos e adicione aulas de vídeo, áudio, PDF, leitura, quiz ou animação. O curso começa pausado; libere-o no catálogo quando estiver pronto.',
            ),
            const SizedBox(height: 24),
            ManagementField(
              label: 'Título do curso',
              labelAbove: true,
              controller: _title,
              requiredValue: true,
              enabled: !_busy,
            ),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_busy ? 'Criando...' : 'Criar curso'),
            ),
          ],
        ),
      ),
    ),
  );
}
