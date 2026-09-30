import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import 'audience_picker.dart';

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
  ConsumerState<PublishVideoScreen> createState() => _PublishVideoScreenState();
}

class _PublishVideoScreenState extends ConsumerState<PublishVideoScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _module = TextEditingController(text: 'Módulo 1');
  final _video = TextEditingController();
  ContentAudience _audience = const ContentAudience();
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [_title, _description, _module, _video]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _publish() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(contentRepositoryProvider)
          .publishVideo(
            title: _title.text,
            description: _description.text,
            moduleTitle: _module.text,
            videoId: youtubeVideoId(_video.text)!,
            audience: _audience,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trilha publicada.')));
      context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível publicar a trilha. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar Trilha'),
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: _saving ? null : () => context.pop(),
          icon: const SvgIcon(AppIcons.arrowBack),
        ),
      ),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Tipo de conteúdo'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in const [
                    ('Vídeo', AppIcons.play),
                    ('Áudio', AppIcons.headphones),
                    ('PDF', AppIcons.pdf),
                    ('Quiz', AppIcons.quiz),
                  ])
                    Chip(
                      avatar: SvgIcon(
                        entry.$2,
                        size: 18,
                        color: entry.$1 == 'Vídeo'
                            ? Colors.white
                            : AppColors.navy,
                      ),
                      label: Text(entry.$1),
                      backgroundColor: entry.$1 == 'Vídeo'
                          ? AppColors.navy
                          : AppColors.chipBg,
                      labelStyle: TextStyle(
                        color: entry.$1 == 'Vídeo'
                            ? Colors.white
                            : AppColors.navy,
                      ),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 20),
                child: Text(
                  'Vídeos são publicados pelo YouTube. Uploads de áudio/PDF e criação de quizzes ainda não estão disponíveis.',
                ),
              ),
              TextFormField(
                controller: _title,
                enabled: !_saving,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o título.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _module,
                enabled: !_saving,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Módulo'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o módulo.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                enabled: !_saving,
                maxLines: 3,
                maxLength: 10000,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _video,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'URL ou ID do YouTube',
                  hintText: 'https://youtu.be/...',
                ),
                validator: (value) => youtubeVideoId(value ?? '') == null
                    ? 'Informe uma URL ou ID válido do YouTube.'
                    : null,
              ),
              const SizedBox(height: 24),
              const SectionHeader('Liberar para:'),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final selection = await pickContentAudience(
                          context,
                          _audience,
                        );
                        if (selection != null && mounted) {
                          setState(() => _audience = selection);
                        }
                      },
                icon: const SvgIcon(
                  AppIcons.companies,
                  color: AppColors.successDarkGreen,
                  size: 20,
                ),
                label: Text(_audience.label),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                _saving ? 'Publicando...' : 'Publicar',
                onPressed: _saving ? null : _publish,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
