import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/admin_styles.dart';
import '../gestor/management_widgets.dart';
import 'lesson_editor.dart';
import '../../app/theme.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/app_icons.dart';
import '../gestor/widgets.dart' show DataSkeleton;
import 'order_controls.dart';

class CourseStructure extends ConsumerStatefulWidget {
  final String courseId;
  final bool disabled;
  const CourseStructure({
    super.key,
    required this.courseId,
    this.disabled = false,
  });
  @override
  ConsumerState<CourseStructure> createState() => _CourseStructureState();
}

class _CourseStructureState extends ConsumerState<CourseStructure> {
  List<ContentModule> _modules = [];
  bool _busy = false, _more = false, _error = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false, bool retainPages = false}) async {
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final rows = <ContentModule>[];
      var more = false;
      final end = retainPages && _modules.isNotEmpty ? _modules.length : 50;
      for (
        var offset = append ? _modules.length : 0;
        offset < (append ? _modules.length + 50 : end);
        offset += 50
      ) {
        final page = await ref
            .read(contentRepositoryProvider)
            .modules(widget.courseId, offset: offset);
        rows.addAll(page);
        more = page.length == 50;
        if (!more) break;
      }
      if (mounted) {
        setState(() {
          _modules = [if (append) ..._modules, ...rows];
          _more = more;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(ContentModule module, int direction) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(contentRepositoryProvider)
          .moveItem('module', module.id, direction);
      if (mounted) await _load(retainPages: true);
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível alterar a ordem dos módulos. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _module([ContentModule? module]) async {
    var draft = module?.title ?? '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(module == null ? 'Adicionar módulo' : 'Renomear módulo'),
        content: TextFormField(
          initialValue: draft,
          onChanged: (value) => draft = value,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Título do módulo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              if (draft.trim().isNotEmpty) {
                Navigator.pop(context, draft.trim());
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(contentRepositoryProvider)
          .saveModule(widget.courseId, title, id: module?.id);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        showManagementMessage(context, 'Não foi possível salvar o módulo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton(
      tooltip: 'Adicionar módulo',
      backgroundColor: AppColors.primary,
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white, width: 2),
      ),
      onPressed: _busy || widget.disabled ? null : _module,
      child: const SvgIcon(AppIcons.plus, color: Colors.white, size: 24),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
      children: [
        const Text('Módulos do curso', style: AdminStyles.cardTitle),
        const SizedBox(height: 8),
        const Text(
          'Adicione um módulo e abra suas aulas para organizar o conteúdo do curso.',
          style: AdminStyles.body,
        ),
        if (_busy && _modules.isEmpty) const DataSkeleton(),
        if (_error)
          TextButton(
            onPressed: () => _load(),
            child: const Text('Falha ao carregar. Tentar novamente'),
          ),
        if (!_busy && !_error && _modules.isEmpty)
          const Text('Adicione o primeiro módulo para cadastrar aulas.'),
        for (final (index, module) in _modules.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MÓDULO ${index + 1}',
                              style: AdminStyles.body.copyWith(
                                color: AppColors.successDarkGreen,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(module.title, style: AdminStyles.cardTitle),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.outlined(
                        tooltip: 'Renomear módulo',
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.successDarkGreen,
                          side: const BorderSide(color: AppColors.border),
                          minimumSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _busy || widget.disabled
                            ? null
                            : () => _module(module),
                        icon: const SvgIcon(
                          AppIcons.edit,
                          size: 18,
                          color: AppColors.successDarkGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy || widget.disabled
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ModuleManagementScreen(module: module),
                                ),
                              ),
                        icon: const SvgIcon(
                          AppIcons.book,
                          size: 18,
                          color: AppColors.successDarkGreen,
                        ),
                        label: const Text('Gerenciar aulas'),
                      ),
                      OrderControls(
                        label: 'módulo',
                        onUp: _busy || widget.disabled || index == 0
                            ? null
                            : () => _move(module, -1),
                        onDown:
                            _busy ||
                                widget.disabled ||
                                (index == _modules.length - 1 && !_more)
                            ? null
                            : () => _move(module, 1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (_more)
          TextButton(
            onPressed: _busy ? null : () => _load(append: true),
            child: const Text('Carregar mais módulos'),
          ),
      ],
    ),
  );
}

class ModuleManagementScreen extends StatelessWidget {
  final ContentModule module;
  const ModuleManagementScreen({super.key, required this.module});
  @override
  Widget build(BuildContext context) => ManagementPage(
    title: 'Aulas do módulo',
    fallbackLocation: '/gestor/conteudo',
    child: Theme(
      data: AdminStyles.formTheme(Theme.of(context)).copyWith(
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: AdminStyles.fieldLabel,
            foregroundColor: AppColors.successDarkGreen,
            minimumSize: const Size(0, 44),
          ),
        ),
      ),
      child: ModuleLessons(module: module, disabled: false),
    ),
  );
}

class ModuleLessons extends ConsumerStatefulWidget {
  final ContentModule module;
  final bool disabled;
  const ModuleLessons({
    super.key,
    required this.module,
    required this.disabled,
  });
  @override
  ConsumerState<ModuleLessons> createState() => _ModuleLessonsState();
}

class _ModuleLessonsState extends ConsumerState<ModuleLessons> {
  List<ContentLesson> _items = [];
  bool _loading = true, _error = false, _more = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false, bool retainPages = false}) async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final items = <ContentLesson>[];
      var more = false;
      final end = retainPages && _items.isNotEmpty ? _items.length : 50;
      for (
        var offset = append ? _items.length : 0;
        offset < (append ? _items.length + 50 : end);
        offset += 50
      ) {
        final page = await ref
            .read(contentRepositoryProvider)
            .moduleLessons(widget.module.id, offset: offset);
        items.addAll(page);
        more = page.length == 50;
        if (!more) break;
      }
      if (mounted) {
        setState(() {
          _items = [if (append) ..._items, ...items];
          _more = more;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _move(ContentLesson lesson, int direction) async {
    setState(() => _loading = true);
    try {
      await ref
          .read(contentRepositoryProvider)
          .moveItem('lesson', lesson.id, direction);
      if (mounted) await _load(retainPages: true);
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível alterar a ordem das aulas. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([ContentLesson? lesson]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LessonEditor(module: widget.module, lesson: lesson),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton(
      tooltip: 'Adicionar aula',
      backgroundColor: AppColors.primary,
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white, width: 2),
      ),
      onPressed: widget.disabled || _loading ? null : _edit,
      child: const SvgIcon(AppIcons.plus, size: 24, color: Colors.white),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
      children: [
        Text(widget.module.title, style: AdminStyles.formTitle),
        const SizedBox(height: 8),
        const Text(
          'Cada aula pode combinar texto de apoio com vídeo, áudio, PDF, quiz, imagem ou animação.',
          style: AdminStyles.body,
        ),
        const SizedBox(height: 20),
        if (_loading && _items.isEmpty) const DataSkeleton(),
        if (_error)
          TextButton(
            onPressed: () => _load(),
            child: const Text('Falha ao carregar aulas. Tentar novamente'),
          ),
        for (final (index, lesson) in _items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AULA ${index + 1} · ${lessonTypeLabels[lesson.kind] ?? lesson.kind}',
                    style: AdminStyles.body.copyWith(
                      color: AppColors.successDarkGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(lesson.title, style: AdminStyles.cardTitle),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      OrderControls(
                        label: 'aula',
                        onUp: widget.disabled || _loading || index == 0
                            ? null
                            : () => _move(lesson, -1),
                        onDown:
                            widget.disabled ||
                                _loading ||
                                (index == _items.length - 1 && !_more)
                            ? null
                            : () => _move(lesson, 1),
                      ),
                      TextButton(
                        onPressed: widget.disabled || _loading
                            ? null
                            : () => _edit(lesson),
                        child: const Text('Editar aula'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (!_loading && !_error && _items.isEmpty)
          const Text('Nenhuma aula neste módulo.'),
        if (_more)
          TextButton(
            onPressed: _loading ? null : () => _load(append: true),
            child: const Text('Carregar mais aulas'),
          ),
      ],
    ),
  );
}
