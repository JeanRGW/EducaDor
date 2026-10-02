import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/admin_styles.dart';
import '../gestor/management_widgets.dart';
import '../gestor/widgets.dart';
import 'cover_image.dart';
import 'audience_picker.dart';
import 'professional_picker.dart';
import 'publish_video_screen.dart';

class CourseEditScreen extends ConsumerStatefulWidget {
  final String courseId;
  const CourseEditScreen({super.key, required this.courseId});
  @override
  ConsumerState<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends ConsumerState<CourseEditScreen> {
  late Future<EditableCourse> _course;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _course = ref.read(contentRepositoryProvider).detail(widget.courseId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<EditableCourse>(
    future: _course,
    builder: (context, snapshot) {
      if (snapshot.hasData) return _CourseEditor(course: snapshot.data!);
      return ManagementPage(
        title: 'Detalhes da trilha',
        fallbackLocation: '/gestor/conteudo',
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (snapshot.hasError)
              DataErrorCard(
                message: 'Trilha indisponível. Tente carregar novamente.',
                retry: () => setState(_load),
              )
            else
              const DataSkeleton(),
          ],
        ),
      );
    },
  );
}

class _CourseEditor extends ConsumerStatefulWidget {
  final EditableCourse course;
  const _CourseEditor({required this.course});
  @override
  ConsumerState<_CourseEditor> createState() => _CourseEditorState();
}

class _CourseEditorState extends ConsumerState<_CourseEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _description;
  late ProfessionalOption? _responsible;
  late String? _coverKey;
  late String? _coverUrl;
  Uint8List? _cover;
  Uint8List? _uploadedCover;
  bool _busy = false;
  bool _picking = false;
  late String _audienceLabel;
  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _title = TextEditingController(text: c.title);
    _description = TextEditingController(text: c.description);
    _responsible = c.responsible;
    _coverKey = c.coverKey;
    _coverUrl = c.coverUrl;
    _audienceLabel = c.allCompanies
        ? 'Todas as empresas'
        : 'Empresas selecionadas';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    if (_busy || _picking) return;
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final processed = bytes.length > 20 * 1024 * 1024
          ? null
          : processCoverImage(bytes);
      if (processed == null) {
        showManagementMessage(
          context,
          'Não foi possível usar esta imagem. Escolha outra.',
        );
        return;
      }
      setState(() => _cover = processed);
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível abrir a imagem. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _picking || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(contentRepositoryProvider);
      if (_cover != null && !identical(_cover, _uploadedCover)) {
        final upload = await repo.requestCoverUpload(size: _cover!.length);
        await repo.uploadCoverBytes(putUrl: upload.putUrl, bytes: _cover!);
        _coverKey = upload.key;
        _uploadedCover = _cover;
      }
      await repo.updateMetadata(
        widget.course.id,
        title: _title.text,
        description: _description.text,
        coverKey: _coverKey,
        responsibleId: _responsible?.id,
      );
      if (!mounted) return;
      ref.invalidate(gestorActivityReportProvider);
      if (mounted) showManagementMessage(context, 'Dados da trilha salvos.');
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível salvar a trilha. Seus dados continuam aqui para tentar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editAudience() async {
    if (_busy || _picking) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(contentRepositoryProvider);
      final current = await repo.audience(widget.course.id);
      if (!mounted) return;
      setState(() {
        _audienceLabel = current.label;
      });
      final selected = await pickContentAudience(context, current);
      if (selected == null || !mounted) return;
      await repo.setAudience(widget.course.id, selected);
      if (!mounted) return;
      setState(() {
        _audienceLabel = selected.label;
      });
      ref.invalidate(gestorDashboardProvider);
      ref.invalidate(gestorCompletionProvider);
      showManagementMessage(context, 'Público atualizado.');
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível atualizar o público. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: 'Detalhes da trilha',
    fallbackLocation: '/gestor/conteudo',
    busy: _busy,
    child: Theme(
      data: AdminStyles.formTheme(Theme.of(context)).copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.successDarkGreen,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: AdminStyles.fieldLabel,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.successDarkGreen,
            minimumSize: const Size(0, 44),
            textStyle: AdminStyles.fieldLabel,
          ),
        ),
      ),
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            ManagementField(
              label: 'Título da trilha',
              labelAbove: true,
              controller: _title,
              requiredValue: true,
              enabled: !_busy,
            ),
            ManagementField(
              label: 'Descrição',
              labelAbove: true,
              controller: _description,
              maxLength: 10000,
              lines: 3,
              enabled: !_busy,
            ),
            const Text('Imagem de capa', style: AdminStyles.fieldLabel),
            const SizedBox(height: 6),
            if (_cover != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _cover!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else if (_coverUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _coverUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 60,
                    child: Center(
                      child: Text('Capa indisponível', style: AdminStyles.body),
                    ),
                  ),
                ),
              ),
            if (_cover != null || _coverUrl != null) const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy || _picking ? null : _pickCover,
                  child: Text(
                    _picking
                        ? 'Preparando imagem...'
                        : 'Alterar imagem de capa',
                  ),
                ),
                if (_cover != null || _coverKey != null)
                  TextButton(
                    onPressed: _busy || _picking
                        ? null
                        : () => setState(() {
                            _cover = null;
                            _uploadedCover = null;
                            _coverKey = null;
                            _coverUrl = null;
                          }),
                    child: const Text('Remover capa'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            ManagementSelector(
              label: 'Profissional responsável',
              value: _responsible?.name ?? 'Selecionar',
              icon: AppIcons.profile,
              onPressed: _busy
                  ? null
                  : () async {
                      final responsible = await pickProfessional(
                        context,
                        _responsible,
                      );
                      if (responsible != null && mounted) {
                        setState(() => _responsible = responsible);
                      }
                    },
            ),
            if (_responsible != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _responsible = null),
                  child: const Text('Remover responsável'),
                ),
              ),
            const SizedBox(height: 12),
            ManagementSelector(
              label: 'Liberar para',
              value: _audienceLabel,
              icon: AppIcons.companies,
              onPressed: _busy || _picking ? null : _editAudience,
            ),
            const SizedBox(height: 6),
            Text(
              'A alteração de público é aplicada ao confirmar a seleção.',
              style: AdminStyles.body.copyWith(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              _busy ? 'Salvando...' : 'Salvar dados da trilha',
              compact: true,
              color: AppColors.successDarkGreen,
              onPressed: _busy || _picking ? null : _save,
            ),
            const SizedBox(height: 24),
            _CourseLessons(
              courseId: widget.course.id,
              disabled: _busy || _picking,
            ),
          ],
        ),
      ),
    ),
  );
}

class _CourseLessons extends ConsumerStatefulWidget {
  final String courseId;
  final bool disabled;
  const _CourseLessons({required this.courseId, required this.disabled});
  @override
  ConsumerState<_CourseLessons> createState() => _CourseLessonsState();
}

class _CourseLessonsState extends ConsumerState<_CourseLessons> {
  List<EditableLesson> _lessons = [];
  bool _loading = true;
  bool _error = false;
  bool _more = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final lessons = await ref
          .read(contentRepositoryProvider)
          .editableLessons(
            widget.courseId,
            offset: append ? _lessons.length : 0,
          );
      if (mounted) {
        setState(() {
          _lessons = [if (append) ..._lessons, ...lessons];
          _more = lessons.length == 50;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('Módulos e aulas', style: AdminStyles.cardTitle),
      ),
      if (_error)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Não foi possível carregar aulas.',
                style: AdminStyles.body,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.disabled || _loading ? null : () => _load(),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      if (_loading) const DataSkeleton(),
      if (!_loading && !_error && _lessons.isEmpty)
        const Text('Nenhuma aula cadastrada.', style: AdminStyles.body),
      for (final lesson in _lessons)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lesson.moduleTitle, style: AdminStyles.fieldLabel),
                const SizedBox(height: 4),
                Text(lesson.title, style: AdminStyles.cardTitle),
                if (lesson.kind == 'video') ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    'https://youtu.be/${lesson.videoId ?? ''}',
                    style: AdminStyles.body,
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.disabled || _loading
                        ? null
                        : () async {
                            final saved = await Navigator.of(context)
                                .push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        _LessonEditor(lesson: lesson),
                                  ),
                                );
                            if (saved == true && mounted) await _load();
                          },
                    child: const Text('Editar aula'),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (_more)
        TextButton(
          onPressed: _loading || widget.disabled
              ? null
              : () => _load(append: true),
          child: const Text('Carregar mais aulas'),
        ),
    ],
  );
}

class _LessonEditor extends ConsumerStatefulWidget {
  final EditableLesson lesson;
  const _LessonEditor({required this.lesson});
  @override
  ConsumerState<_LessonEditor> createState() => _LessonEditorState();
}

class _LessonEditorState extends ConsumerState<_LessonEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _module, _video;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.lesson.title);
    _module = TextEditingController(text: widget.lesson.moduleTitle);
    _video = TextEditingController(text: widget.lesson.videoId ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _module.dispose();
    _video.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final videoId = widget.lesson.kind == 'video'
        ? youtubeVideoId(_video.text)
        : null;
    if (widget.lesson.kind == 'video' &&
        videoId != widget.lesson.videoId &&
        !await confirmManagementAction(
          context,
          title: 'Substituir vídeo?',
          message:
              'O vídeo será substituído, mas as conclusões e posições de reprodução já registradas serão mantidas.',
          action: 'Substituir vídeo',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(contentRepositoryProvider)
          .updateLesson(
            widget.lesson.id,
            moduleTitle: _module.text,
            title: _title.text,
            videoId: videoId,
          );
      if (mounted) {
        showManagementMessage(context, 'Aula atualizada.');
        leaveManagementPage(context, '/gestor/conteudo', result: true);
      }
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível salvar a aula. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: 'Editar aula',
    fallbackLocation: '/gestor/conteudo',
    busy: _busy,
    child: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ManagementField(
            label: 'Título do módulo',
            controller: _module,
            requiredValue: true,
            enabled: !_busy,
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'O nome do módulo é compartilhado por todas as suas aulas.',
            ),
          ),
          ManagementField(
            label: 'Título da aula',
            controller: _title,
            requiredValue: true,
            enabled: !_busy,
          ),
          if (widget.lesson.kind == 'video')
            ManagementField(
              label: 'Vídeo do YouTube',
              controller: _video,
              enabled: !_busy,
              maxLength: 500,
              validator: (value) => youtubeVideoId(value ?? '') == null
                  ? 'Informe uma URL ou ID válido.'
                  : null,
            ),
          PrimaryButton(
            _busy ? 'Salvando...' : 'Salvar aula',
            compact: true,
            color: AppColors.successDarkGreen,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    ),
  );
}
