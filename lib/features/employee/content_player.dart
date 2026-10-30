import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/repositories/employee_providers.dart';
import '../../data/session/playback_progress.dart';
import '../content/animated_lesson.dart';
import '../gestor/management_widgets.dart' show leaveManagementPage;
import '../../shared/widgets/app_icons.dart';

class ContentPlayer extends ConsumerStatefulWidget {
  final EmployeeLesson lesson;
  final String courseId;
  const ContentPlayer({
    super.key,
    required this.lesson,
    required this.courseId,
  });
  @override
  ConsumerState<ContentPlayer> createState() => _ContentPlayerState();
}

class _LoadedContent {
  final ContentLesson lesson;
  final List<String> urls;
  final Uint8List? pdf;
  _LoadedContent(this.lesson, this.urls, this.pdf);
}

class _ContentPlayerState extends ConsumerState<ContentPlayer> {
  late Future<_LoadedContent> _content;
  late final PlaybackProgress _progress;
  final _answers = <int, int>{};
  bool _busy = false, _complete = false;
  bool _manualBack = false;
  String? _feedback;
  @override
  void initState() {
    super.initState();
    _content = _load();
    _complete = widget.lesson.completed;
    final scope = ref.read(employeeScopeProvider);
    _progress = PlaybackProgress(
      repository: ref.read(progressRepositoryProvider),
      companyId: scope.companyId,
      lessonId: widget.lesson.id,
      isCurrent: () => mounted && ref.read(employeeScopeProvider) == scope,
      positionSec: widget.lesson.positionSec,
      completed: widget.lesson.completed,
    );
  }

  Future<_LoadedContent> _load() async {
    final repo = ref.read(contentRepositoryProvider);
    final lesson = await repo.lesson(widget.lesson.id);
    final data = lesson.data;
    final file = data['file_key'] as String?;
    final keys = (data['image_keys'] as List<dynamic>? ?? []).cast<String>();
    final urls = lesson.kind != 'pdf' && (file != null || keys.isNotEmpty)
        ? await repo.lessonFileUrls(lesson.id, [?file, ...keys])
        : <String>[];
    return _LoadedContent(
      lesson,
      urls,
      lesson.kind == 'pdf' && file != null
          ? await repo.lessonFileBytes(lesson.id, file)
          : null,
    );
  }

  Future<void> _finish(ContentLesson lesson) async {
    if (lesson.kind == 'quiz') {
      final questions = lesson.data['quiz_json'] as List<dynamic>;
      final correct = questions.asMap().entries.every(
        (e) => _answers[e.key] == (e.value as Map<String, dynamic>)['answer'],
      );
      if (!correct) {
        setState(
          () => _feedback =
              'Revise suas respostas. Acerte todas as perguntas para concluir.',
        );
        return;
      }
    }
    setState(() => _busy = true);
    try {
      _progress.completed = true;
      await _progress.save(force: true);
      if (mounted) {
        setState(() {
          _complete = true;
          _feedback = 'Aula concluída.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback =
              'Não foi possível registrar a conclusão. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkpoint({bool force = false}) async {
    try {
      await _progress.save(force: force);
      if (mounted && _progress.completed) setState(() => _complete = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback =
              'Não foi possível salvar o progresso do áudio. Pause para tentar novamente.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && !_manualBack && widget.lesson.kind == 'audio') {
        unawaited(_checkpoint(force: true));
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.lesson.title),
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: _busy
              ? null
              : () async {
                  if (widget.lesson.kind == 'audio') {
                    await _checkpoint(force: true);
                  }
                  if (context.mounted) {
                    _manualBack = true;
                    leaveManagementPage(
                      context,
                      '/funcionario/course/${widget.courseId}',
                    );
                  }
                },
          icon: const SvgIcon(AppIcons.arrowBack),
        ),
      ),
      body: FutureBuilder<_LoadedContent>(
        future: _content,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _content = _load()),
                child: const Text('Falha ao carregar. Tentar novamente'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox(width: 240, child: LinearProgressIndicator()),
            );
          }
          final content = snapshot.data!;
          final data = content.lesson.data;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.lesson.moduleTitle,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 16),
              if ((data['body'] as String? ?? '').trim().isNotEmpty) ...[
                SelectableText(data['body'] as String),
                const SizedBox(height: 20),
              ],
              if (content.lesson.kind == 'audio' && content.urls.isNotEmpty)
                _AudioLesson(
                  url: content.urls.first,
                  startSec: widget.lesson.positionSec,
                  onPosition: (position, duration) {
                    _progress.update(position, duration);
                    if (_progress.needsCheckpoint) unawaited(_checkpoint());
                  },
                  onPause: () => _checkpoint(force: true),
                ),
              if (content.lesson.kind == 'pdf' && content.pdf != null)
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.7,
                  child: PdfPreview(
                    build: (_) => content.pdf!,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                  ),
                ),
              if (content.lesson.kind == 'animation' &&
                  content.urls.isNotEmpty &&
                  data['file_key'] is String &&
                  !(data['file_key'] as String).endsWith('.gif'))
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      content.urls.single,
                      fit: BoxFit.contain,
                      semanticLabel: widget.lesson.title,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          'Imagem indisponível. Reabra a aula para tentar novamente.',
                        ),
                      ),
                    ),
                  ),
                )
              else if (content.lesson.kind == 'animation')
                AnimatedLesson(
                  urls: content.urls,
                  frameMs: data['frame_ms'] as int? ?? 1000,
                  gif: data['file_key'] != null,
                ),
              if (content.lesson.kind == 'quiz') ...[
                for (final entry
                    in (data['quiz_json'] as List<dynamic>? ?? [])
                        .asMap()
                        .entries)
                  _question(entry.key, entry.value as Map<String, dynamic>),
              ],
              const SizedBox(height: 24),
              if (_feedback != null)
                Text(_feedback!, semanticsLabel: _feedback),
              FilledButton(
                onPressed: _busy || _complete
                    ? null
                    : () => _finish(content.lesson),
                child: Text(
                  _complete
                      ? 'Concluída'
                      : _busy
                      ? 'Salvando...'
                      : 'Concluir aula',
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  Widget _question(int index, Map<String, dynamic> question) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${index + 1}. ${question['question']}'),
          const SizedBox(height: 8),
          RadioGroup<int>(
            groupValue: _answers[index],
            onChanged: (v) {
              if (v != null && !_complete && !_busy) {
                setState(() => _answers[index] = v);
              }
            },
            child: Column(
              children: [
                for (final entry
                    in (question['options'] as List<dynamic>).asMap().entries)
                  RadioListTile<int>(
                    value: entry.key,
                    title: Text(entry.value as String),
                    enabled: !_complete && !_busy,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AudioLesson extends StatefulWidget {
  final String url;
  final int startSec;
  final void Function(Duration, Duration) onPosition;
  final Future<void> Function() onPause;
  const _AudioLesson({
    required this.url,
    required this.startSec,
    required this.onPosition,
    required this.onPause,
  });
  @override
  State<_AudioLesson> createState() => _AudioLessonState();
}

class _AudioLessonState extends State<_AudioLesson>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  bool _playing = false;
  String? _error;
  StreamSubscription<void>? _ended;
  StreamSubscription<Duration>? _positions, _durations;
  Duration _position = Duration.zero, _duration = Duration.zero;
  bool _loaded = false, _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _position = Duration(seconds: widget.startSec);
    _positions = _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
      widget.onPosition(position, _duration);
    });
    _durations = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _ended = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _loaded = false;
        });
        widget.onPosition(_duration, _duration);
        unawaited(widget.onPause());
      }
    });
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_playing) {
        await _player.pause();
        await widget.onPause();
      } else {
        if (_loaded) {
          await _player.resume();
        } else {
          await _player.play(UrlSource(widget.url), position: _position);
          _loaded = true;
        }
      }
      if (mounted) {
        setState(() {
          _playing = !_playing;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Não foi possível reproduzir o áudio. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _seek(double seconds) async {
    try {
      final position = Duration(seconds: seconds.round());
      if (_loaded) await _player.seek(position);
      if (mounted) setState(() => _position = position);
      widget.onPosition(position, _duration);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível alterar a posição.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) {
      unawaited(_toggle());
    }
  }

  @override
  void dispose() {
    _ended?.cancel();
    _positions?.cancel();
    _durations?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      OutlinedButton(
        onPressed: _busy ? null : _toggle,
        child: Text(_playing ? 'Pausar áudio' : 'Reproduzir áudio'),
      ),
      if (_duration > Duration.zero)
        Slider(
          value: _position.inSeconds.toDouble().clamp(
            0,
            _duration.inSeconds.toDouble(),
          ),
          max: _duration.inSeconds.toDouble(),
          onChanged: _busy ? null : _seek,
          label: '${_position.inSeconds}s',
        ),
      Text(
        '${_position.inSeconds}s${_duration > Duration.zero ? ' / ${_duration.inSeconds}s' : ''}',
      ),
      if (_error != null) Text(_error!),
    ],
  );
}
