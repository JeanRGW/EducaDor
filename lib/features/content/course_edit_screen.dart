import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../app/theme.dart';
import '../gestor/management_widgets.dart';
import '../gestor/widgets.dart';
import 'audience_picker.dart';
import 'professional_picker.dart';
import 'cover_image.dart';
import 'course_structure.dart';
import 'delete_content.dart';

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
        title: 'Detalhes do curso',
        fallbackLocation: '/gestor/conteudo',
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (snapshot.hasError)
              DataErrorCard(
                message: 'Curso indisponível. Tente carregar novamente.',
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
  ProfessionalOption? _responsible;
  String? _coverKey, _coverUrl;
  Uint8List? _cover, _uploadedCover;
  bool _busy = false;
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
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final processed = bytes.length > 20 * 1024 * 1024
          ? null
          : processCoverImage(bytes);
      if (processed == null) throw StateError('Invalid image');
      if (mounted) setState(() => _cover = processed);
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível usar esta imagem. Escolha outra.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
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
      ref.invalidate(gestorActivityReportProvider);
      if (mounted) showManagementMessage(context, 'Dados do curso salvos.');
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível salvar o curso. Seus dados continuam aqui para tentar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _audience() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(contentRepositoryProvider);
      final current = await repo.audience(widget.course.id);
      if (!mounted) return;
      final selected = await pickContentAudience(context, current);
      if (selected == null || !mounted) return;
      await repo.setAudience(widget.course.id, selected);
      if (mounted) setState(() => _audienceLabel = selected.label);
      ref.invalidate(gestorDashboardProvider);
      ref.invalidate(gestorCompletionProvider);
      if (mounted) showManagementMessage(context, 'Público atualizado.');
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

  Future<void> _delete() async {
    if (!await confirmContentDeletion(context, 'course', widget.course.title) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(contentRepositoryProvider)
          .deleteContent('course', widget.course.id);
      ref.invalidate(gestorDashboardProvider);
      ref.invalidate(gestorCompletionProvider);
      ref.invalidate(gestorActivityReportProvider);
      if (mounted) leaveManagementPage(context, '/gestor/conteudo');
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível excluir o curso. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: 'Detalhes do curso',
    fallbackLocation: '/gestor/conteudo',
    busy: _busy,
    child: Theme(
      data: AdminStyles.formTheme(Theme.of(context)).copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.successDarkGreen,
            minimumSize: const Size(0, 44),
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
            textStyle: AdminStyles.fieldLabel,
            minimumSize: const Size(0, 44),
          ),
        ),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Material(
              color: AppColors.surface,
              child: TabBar(
                labelStyle: AdminStyles.fieldLabel,
                unselectedLabelStyle: AdminStyles.fieldLabel,
                labelColor: AppColors.successDarkGreen,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.successDarkGreen,
                tabs: const [
                  Tab(text: 'Dados do curso'),
                  Tab(text: 'Módulos e aulas'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              const Text(
                                'Informações do curso',
                                style: AdminStyles.cardTitle,
                              ),
                              const SizedBox(height: 16),
                              ManagementField(
                                label: 'Título do curso',
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
                              const Text(
                                'Imagem de capa',
                                style: AdminStyles.fieldLabel,
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: _cover != null
                                      ? Image.memory(
                                          _cover!,
                                          height: 140,
                                          fit: BoxFit.cover,
                                        )
                                      : _coverUrl != null
                                      ? Image.network(
                                          _coverUrl!,
                                          height: 140,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              const Text('Capa indisponível'),
                                        )
                                      : Container(
                                          height: 100,
                                          color: AppColors.successBgSoft,
                                          child: const Center(
                                            child: SvgIcon(
                                              AppIcons.book,
                                              size: 32,
                                              color: AppColors.successDarkGreen,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: _busy ? null : _pickCover,
                                    child: const Text('Alterar imagem de capa'),
                                  ),
                                  if (_coverKey != null || _cover != null)
                                    TextButton(
                                      onPressed: _busy
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
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 16),
                              const Text(
                                'Responsável e acesso',
                                style: AdminStyles.cardTitle,
                              ),
                              const SizedBox(height: 16),
                              ManagementSelector(
                                label: 'Profissional responsável',
                                value: _responsible?.name ?? 'Selecionar',
                                icon: AppIcons.profile,
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final person = await pickProfessional(
                                          context,
                                          _responsible,
                                        );
                                        if (person != null && mounted) {
                                          setState(() => _responsible = person);
                                        }
                                      },
                              ),
                              if (_responsible != null)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () =>
                                            setState(() => _responsible = null),
                                  child: const Text('Remover responsável'),
                                ),
                              ManagementSelector(
                                label: 'Liberar para',
                                value: _audienceLabel,
                                icon: AppIcons.companies,
                                onPressed: _busy ? null : _audience,
                              ),
                              const Text(
                                'A alteração de público é aplicada ao confirmar a seleção.',
                                style: AdminStyles.body,
                              ),
                              const SizedBox(height: 20),
                              const SizedBox(height: 24),
                              TextButton(
                                onPressed: _busy ? null : _delete,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                ),
                                child: const Text('Excluir curso'),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            border: Border(
                              top: BorderSide(color: AppColors.border),
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child: FilledButton(
                              onPressed: _busy ? null : _save,
                              child: Text(
                                _busy ? 'Salvando...' : 'Salvar dados do curso',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  CourseStructure(courseId: widget.course.id, disabled: _busy),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
