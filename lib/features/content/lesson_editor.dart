import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../gestor/management_widgets.dart';
import 'publish_video_screen.dart' show youtubeVideoId;
import '../../shared/widgets/admin_styles.dart';

class LessonEditor extends ConsumerStatefulWidget {
  final ContentModule module;
  final ContentLesson? lesson;
  const LessonEditor({super.key, required this.module, this.lesson});
  @override
  ConsumerState<LessonEditor> createState() => _LessonEditorState();
}

class _LessonEditorState extends ConsumerState<LessonEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _points;
  late final _LessonDraft _primary;
  _LessonDraft? _alternate;
  String? _gender;
  late String _kind;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final data = widget.lesson?.data ?? {};
    _kind = widget.lesson?.kind ?? 'video';
    _title = TextEditingController(text: widget.lesson?.title);
    _points = TextEditingController(text: '${data['points'] ?? 10}');
    _gender = data['content_gender'] as String?;
    _primary = _LessonDraft(data, primary: true);
    final alternate = data['alternate_content'];
    if (alternate is Map) {
      _alternate = _LessonDraft(Map<String, dynamic>.from(alternate));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _points.dispose();
    _primary.dispose();
    _alternate?.dispose();
    super.dispose();
  }

  Future<void> _pick(
    _LessonDraft draft, {
    bool sequence = false,
    bool image = false,
  }) async {
    setState(() => _busy = true);
    try {
      final extensions = sequence || image
          ? ['png', 'jpg', 'jpeg', 'webp']
          : switch (_kind) {
              'audio' => ['mp3'],
              'pdf' => ['pdf'],
              _ => ['gif'],
            };
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        allowMultiple: sequence,
        withData: false,
        withReadStream: true,
      );
      if (result == null || !mounted) return;
      if (sequence && (result.files.length < 2 || result.files.length > 100)) {
        throw StateError('Choose 2–100 frames');
      }
      final uploads = <String>[];
      for (final file in result.files) {
        if (file.size < 1 || file.size > 50 * 1024 * 1024) {
          throw StateError('Invalid file');
        }
        final buffer = BytesBuilder(copy: false);
        final stream = file.readStream;
        if (stream == null) throw StateError('File cannot be read');
        await for (final chunk in stream) {
          if (buffer.length + chunk.length > 50 * 1024 * 1024) {
            throw StateError('File too large');
          }
          buffer.add(chunk);
        }
        final bytes = buffer.takeBytes();
        if (!mounted) return;
        final mime = switch (file.extension?.toLowerCase()) {
          'mp3' => 'audio/mpeg',
          'pdf' => 'application/pdf',
          'gif' => 'image/gif',
          'png' => 'image/png',
          'jpg' || 'jpeg' => 'image/jpeg',
          'webp' => 'image/webp',
          _ => throw StateError('Invalid format'),
        };
        uploads.add(
          await ref
              .read(contentRepositoryProvider)
              .uploadLessonFile(bytes, mime),
        );
      }
      if (!mounted) return;
      setState(() {
        if (sequence) {
          draft.keys = uploads;
          draft.fileKey = null;
        } else {
          draft.fileKey = uploads.single;
          draft.keys = [];
        }
      });
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível enviar. Use o formato indicado, até 50 MB por arquivo; sequências devem ter de 2 a 100 imagens.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    for (final draft in [_primary, ?_alternate]) {
      if ((['audio', 'pdf'].contains(_kind) && draft.fileKey == null) ||
          (_kind == 'animation' &&
              draft.fileKey == null &&
              (draft.keys.length < 2 || draft.keys.length > 100))) {
        showManagementMessage(
          context,
          'Envie o arquivo de cada versão antes de salvar.',
        );
        return;
      }
    }
    if (widget.lesson != null &&
        !await confirmManagementAction(
          context,
          title: 'Salvar alterações na aula?',
          message:
              'O conteúdo será atualizado. As conclusões e o progresso existentes serão mantidos.',
          action: 'Salvar aula',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(contentRepositoryProvider)
          .saveContentLesson(
            moduleId: widget.module.id,
            title: _title.text,
            kind: _kind,
            id: widget.lesson?.id,
            data: {
              'points': int.parse(_points.text.trim()),
              ..._primary.toJson(),
              'content_gender': _gender,
              'alternate_content': _alternate?.toJson(),
            },
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        showManagementMessage(
          context,
          'Não foi possível salvar a aula. Seus dados foram mantidos.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: widget.lesson == null ? 'Adicionar aula' : 'Editar aula',
    fallbackLocation: '/gestor/conteudo',
    busy: _busy,
    child: Theme(
      data: AdminStyles.formTheme(Theme.of(context)),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                widget.module.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ManagementField(
                label: 'Título da aula',
                labelAbove: true,
                controller: _title,
                requiredValue: true,
                enabled: !_busy,
              ),
              ManagementField(
                label: 'Pontos da aula',
                labelAbove: true,
                controller: _points,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                validator: (value) {
                  final points = int.tryParse(value?.trim() ?? '');
                  // Match PostgreSQL's integer column; it has no positivity rule.
                  return points == null ||
                          points < -2147483648 ||
                          points > 2147483647
                      ? 'Informe um número inteiro entre -2147483648 e 2147483647.'
                      : null;
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Tipo da aula'),
                items: lessonTypeLabels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: _busy || widget.lesson != null
                    ? null
                    : (value) => setState(() {
                        _kind = value!;
                        _primary.fileKey = null;
                        _primary.keys = [];
                        _alternate?.fileKey = null;
                        _alternate?.keys = [];
                      }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _gender ?? 'neutral',
                decoration: const InputDecoration(
                  labelText: 'Versão principal',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'neutral',
                    child: Text('Neutra / compartilhada'),
                  ),
                  DropdownMenuItem(value: 'male', child: Text('Masculina')),
                  DropdownMenuItem(value: 'female', child: Text('Feminina')),
                ],
                onChanged: _busy || _alternate != null
                    ? null
                    : (value) => setState(
                        () => _gender = value == 'neutral' ? null : value,
                      ),
              ),
              const Text(
                'As versões são da mesma aula e compartilham pontos e progresso; não restringem o público. Uma única versão é exibida para todas as pessoas. Sem gênero informado, usa-se a versão principal.',
              ),
              if (_gender != null && _alternate == null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _alternate = _LessonDraft({})),
                  child: Text(
                    _gender == 'male'
                        ? 'Adicionar versão feminina'
                        : 'Adicionar versão masculina',
                  ),
                ),
              for (final draft in [_primary, ?_alternate]) ...[
                const SizedBox(height: 16),
                Text(
                  identical(draft, _primary)
                      ? 'Conteúdo principal'
                      : (_gender == 'male'
                            ? 'Conteúdo feminino'
                            : 'Conteúdo masculino'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!identical(draft, _primary))
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!await confirmManagementAction(
                              context,
                              title: 'Remover versão?',
                              message:
                                  'A versão alternativa será removida da aula. O progresso será mantido; arquivos enviados não são apagados.',
                              action: 'Remover',
                            )) {
                              return;
                            }
                            if (!mounted) return;
                            final removed = _alternate;
                            setState(() => _alternate = null);
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => removed?.dispose(),
                            );
                          },
                    child: const Text('Remover versão alternativa'),
                  ),
                if (_kind == 'video')
                  ManagementField(
                    label: 'URL ou ID do YouTube',
                    controller: draft.video,
                    enabled: !_busy,
                    maxLength: 500,
                    validator: (v) => youtubeVideoId(v ?? '') == null
                        ? 'Informe um vídeo válido do YouTube.'
                        : null,
                  ),
                ManagementField(
                  label: _kind == 'reading'
                      ? 'Texto da aula'
                      : 'Texto de apoio (opcional)',
                  controller: draft.body,
                  labelAbove: true,
                  lines: _kind == 'reading' ? 12 : 4,
                  maxLength: 100000,
                  requiredValue: _kind == 'reading',
                  enabled: !_busy,
                ),
                if (['audio', 'pdf', 'animation'].contains(_kind)) ...[
                  Text(
                    draft.fileKey == null
                        ? 'Nenhum arquivo selecionado.'
                        : 'Arquivo enviado: ${draft.fileKey!.split('/').last}',
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _pick(draft),
                    child: Text(switch (_kind) {
                      'audio' => 'Enviar MP3',
                      'pdf' => 'Enviar PDF',
                      _ => 'Enviar GIF',
                    }),
                  ),
                ],
                if (_kind == 'animation') ...[
                  OutlinedButton(
                    onPressed: _busy ? null : () => _pick(draft, image: true),
                    child: const Text('Enviar imagem (PNG, JPG ou WebP)'),
                  ),
                  const Text(
                    'Ou envie imagens e organize a ordem dos quadros.',
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _pick(draft, sequence: true),
                    child: const Text('Enviar sequência de imagens'),
                  ),
                  if (draft.keys.isNotEmpty)
                    ManagementField(
                      label: 'Duração de cada quadro (ms)',
                      controller: draft.interval,
                      enabled: !_busy,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 100 || n > 10000
                            ? 'Use de 100 a 10000 ms.'
                            : null;
                      },
                    ),
                  for (var i = 0; i < draft.keys.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Quadro ${i + 1}'),
                            Text(draft.keys[i].split('/').last),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _busy || i == 0
                                      ? null
                                      : () => setState(() {
                                          final key = draft.keys.removeAt(i);
                                          draft.keys.insert(i - 1, key);
                                        }),
                                  child: const Text('Subir'),
                                ),
                                TextButton(
                                  onPressed: _busy || i == draft.keys.length - 1
                                      ? null
                                      : () => setState(() {
                                          final key = draft.keys.removeAt(i);
                                          draft.keys.insert(i + 1, key);
                                        }),
                                  child: const Text('Descer'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (_kind == 'quiz') ...[
                  const Text(
                    'Cada pergunta tem uma resposta correta. Acerte todas para concluir.',
                  ),
                  for (var i = 0; i < draft.questions.length; i++)
                    _question(draft, draft.questions[i], i),
                  TextButton(
                    onPressed: _busy || draft.questions.length >= 50
                        ? null
                        : () => setState(
                            () => draft.questions.add(_QuestionDraft()),
                          ),
                    child: const Text('Adicionar pergunta'),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Salvando...' : 'Salvar aula'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _question(_LessonDraft draft, _QuestionDraft q, int index) => Card(
    key: ObjectKey(q),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          ManagementField(
            label: 'Pergunta ${index + 1}',
            controller: q.question,
            maxLength: 1000,
            requiredValue: true,
            enabled: !_busy,
          ),
          for (var i = 0; i < q.options.length; i++)
            ManagementField(
              label: 'Alternativa ${i + 1}',
              controller: q.options[i],
              maxLength: 500,
              requiredValue: true,
              enabled: !_busy,
            ),
          DropdownButtonFormField<int>(
            initialValue: q.answer,
            decoration: const InputDecoration(labelText: 'Resposta correta'),
            items: List.generate(
              q.options.length,
              (i) => DropdownMenuItem(
                value: i,
                child: Text('Alternativa ${i + 1}'),
              ),
            ),
            onChanged: _busy ? null : (v) => setState(() => q.answer = v!),
          ),
          if (draft.questions.length > 1)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      draft.questions.remove(q);
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => q.dispose(),
                      );
                    }),
              child: const Text('Remover pergunta'),
            ),
        ],
      ),
    ),
  );
}

class _LessonDraft {
  late final TextEditingController body, video, interval;
  String? fileKey;
  List<String> keys;
  final questions = <_QuestionDraft>[];

  _LessonDraft(Map<String, dynamic> data, {bool primary = false})
    : fileKey = data['file_key'] as String?,
      keys = (data['image_keys'] as List<dynamic>? ?? [])
          .cast<String>()
          .toList() {
    body = TextEditingController(text: data['body'] as String?);
    video = TextEditingController(text: data['video_id'] as String?);
    interval = TextEditingController(text: '${data['frame_ms'] ?? 1000}');
    for (final q
        in data[primary ? 'quiz_json' : 'questions'] as List<dynamic>? ?? []) {
      questions.add(
        _QuestionDraft.fromJson(Map<String, dynamic>.from(q as Map)),
      );
    }
    if (questions.isEmpty) questions.add(_QuestionDraft());
  }

  Map<String, dynamic> toJson() => {
    'video_id': youtubeVideoId(video.text),
    'body': body.text.trim(),
    'file_key': fileKey,
    'image_keys': keys,
    'frame_ms': int.tryParse(interval.text) ?? 1000,
    'questions': questions.map((q) => q.toJson()).toList(),
  };

  void dispose() {
    body.dispose();
    video.dispose();
    interval.dispose();
    for (final q in questions) {
      q.dispose();
    }
  }
}

class _QuestionDraft {
  final TextEditingController question;
  final List<TextEditingController> options;
  int answer;
  _QuestionDraft()
    : question = TextEditingController(),
      options = List.generate(4, (_) => TextEditingController()),
      answer = 0;
  _QuestionDraft.fromJson(Map<String, dynamic> json)
    : question = TextEditingController(text: json['question'] as String),
      options = (json['options'] as List<dynamic>)
          .map((o) => TextEditingController(text: o as String))
          .toList(),
      answer = json['answer'] as int;
  Map<String, dynamic> toJson() => {
    'question': question.text.trim(),
    'options': options.map((c) => c.text.trim()).toList(),
    'answer': answer,
  };
  void dispose() {
    question.dispose();
    for (final c in options) {
      c.dispose();
    }
  }
}
