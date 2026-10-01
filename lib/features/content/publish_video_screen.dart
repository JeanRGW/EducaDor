import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import 'audience_picker.dart';
import 'cover_image.dart';
import 'professional_picker.dart';

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
  ProfessionalOption? _responsible;
  Uint8List? _cover;
  bool _pickingCover = false;
  bool _saving = false;

  static const _types = [
    ('Vídeo', AppIcons.play, true),
    ('Áudio', AppIcons.headphones, false),
    ('PDF', AppIcons.pdf, false),
    ('Quiz', AppIcons.quiz, false),
  ];

  ProfessionalOption? get _effectiveResponsible {
    if (_responsible != null) return _responsible;
    final user = ref.read(sessionProvider).value?.user;
    if (user == null) return null;
    return ProfessionalOption(id: user.id, name: user.fullName);
  }

  @override
  void dispose() {
    for (final controller in [_title, _description, _module, _video]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCover() async {
    if (_pickingCover || _saving) return;
    setState(() => _pickingCover = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted || file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 20 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Imagem muito grande. Escolha outra imagem.'),
            ),
          );
        }
        return;
      }
      final processed = processCoverImage(bytes);
      if (processed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível usar esta imagem.')),
          );
        }
        return;
      }
      setState(() => _cover = processed);
    } finally {
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  Future<void> _publish() async {
    if (!_form.currentState!.validate()) return;
    final responsible = _effectiveResponsible;
    if (responsible == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o profissional responsável.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      String? coverKey;
      if (_cover != null) {
        final upload = await ref
            .read(contentRepositoryProvider)
            .requestCoverUpload(size: _cover!.length);
        await ref
            .read(contentRepositoryProvider)
            .uploadCoverBytes(putUrl: upload.putUrl, bytes: _cover!);
        coverKey = upload.key;
      }
      await ref
          .read(contentRepositoryProvider)
          .publishVideo(
            title: _title.text,
            description: _description.text,
            moduleTitle: _module.text,
            videoId: youtubeVideoId(_video.text)!,
            audience: _audience,
            coverKey: coverKey,
            responsibleId: responsible.id,
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
  Widget build(BuildContext context) {
    // Rebuild once the session resolves so the responsible defaults to the
    // current gestor without an explicit selection.
    ref.watch(sessionProvider);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Adicionar Trilha'),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _saving ? null : () => context.pop(),
            icon: const SvgIcon(
              AppIcons.arrowBack,
              color: AppColors.successDarkGreen,
            ),
          ),
        ),
        body: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('Tipo de conteúdo'),
                Row(
                  children: [
                    for (var i = 0; i < _types.length; i++) ...[
                      Expanded(
                        child: _TypeTile(
                          label: _types[i].$1,
                          icon: _types[i].$2,
                          active: _types[i].$3,
                          onTap: _types[i].$3 || _saving
                              ? null
                              : () => ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Disponível em breve. Por enquanto, publique vídeos do YouTube.',
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (i != _types.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Título'),
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    hintText: 'Dor crônica',
                    counterText: '',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o título.'
                      : null,
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Modulos'),
                TextFormField(
                  controller: _module,
                  enabled: !_saving,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    hintText: 'Modulo 1',
                    counterText: '',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o módulo.'
                      : null,
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Descrição'),
                TextFormField(
                  controller: _description,
                  enabled: !_saving,
                  maxLines: 3,
                  maxLength: 10000,
                  decoration: const InputDecoration(
                    hintText: 'breve descrição da trilha',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Imagem de capa'),
                GestureDetector(
                  onTap: _pickCover,
                  child: Container(
                    height: 110,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                      color: AppColors.chipBg,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_cover != null)
                          Image.memory(_cover!, fit: BoxFit.cover)
                        else
                          const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgIcon(
                                AppIcons.camera,
                                size: 28,
                                color: AppColors.textMuted,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Toque para escolher uma imagem',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        if (_pickingCover)
                          const ColoredBox(
                            color: Color(0x80FFFFFF),
                            child: Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const SvgIcon(
                              AppIcons.camera,
                              color: AppColors.textPrimary,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_cover != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _cover = null),
                      child: const Text('Remover imagem'),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('Vídeo do YouTube'),
                          TextFormField(
                            controller: _video,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              hintText: 'https://youtu.be/...',
                            ),
                            validator: (value) =>
                                youtubeVideoId(value ?? '') == null
                                ? 'Informe uma URL ou ID válido.'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('Profissional Responsavel'),
                          _SelectorButton(
                            value: _effectiveResponsible?.name ?? 'Selecionar',
                            onTap: _saving
                                ? null
                                : () async {
                                    final selection = await pickProfessional(
                                      context,
                                      _responsible,
                                    );
                                    if (selection != null && mounted) {
                                      setState(() => _responsible = selection);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Liberar para:'),
                _SelectorButton(
                  value: _audience.label,
                  onTap: _saving
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
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  _saving ? 'Publicando...' : 'Publicar',
                  color: AppColors.successDarkGreen,
                  onPressed: _saving ? null : _publish,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    ),
  );
}

class _TypeTile extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final VoidCallback? onTap;

  const _TypeTile({
    required this.label,
    required this.icon,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: active ? 1 : 0.65,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.navyDeep : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.navyDeep : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            SvgIcon(
              icon,
              size: 22,
              color: active ? Colors.white : AppColors.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SelectorButton extends StatelessWidget {
  final String value;
  final VoidCallback? onTap;

  const _SelectorButton({required this.value, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.successDarkGreen,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const SvgIcon(
            AppIcons.chevronDown,
            size: 20,
            color: AppColors.successDarkGreen,
          ),
        ],
      ),
    ),
  );
}
