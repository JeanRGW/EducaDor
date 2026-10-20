import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../data/models/models.dart';
import '../../data/repositories/employee_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/playback_progress.dart';
import '../../shared/widgets/app_icons.dart';
import '../gestor/management_widgets.dart' show leaveManagementPage;
import 'widgets.dart';

class EmployeePlayerScreen extends ConsumerWidget {
  final String courseId, lessonId;
  const EmployeePlayerScreen({
    super.key,
    required this.courseId,
    required this.lessonId,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlayerLoader(
    key: ValueKey((ref.watch(employeeScopeProvider), courseId, lessonId)),
    courseId: courseId,
    lessonId: lessonId,
  );
}

class _PlayerLoader extends ConsumerStatefulWidget {
  final String courseId, lessonId;
  const _PlayerLoader({
    super.key,
    required this.courseId,
    required this.lessonId,
  });
  @override
  ConsumerState<_PlayerLoader> createState() => _PlayerLoaderState();
}

class _PlayerLoaderState extends ConsumerState<_PlayerLoader> {
  late Future<EmployeeLesson?> _lesson;
  @override
  void initState() {
    super.initState();
    _lesson = _load();
  }

  Future<EmployeeLesson?> _load() async {
    final scope = ref.read(employeeScopeProvider);
    final repo = ref.read(employeeLearningRepositoryProvider);
    for (var offset = 0; ; offset += 50) {
      final page = await repo.lessons(
        scope.companyId,
        widget.courseId,
        offset: offset,
      );
      for (final lesson in page.items) {
        if (lesson.id == widget.lessonId) return lesson;
      }
      if (offset + page.items.length >= page.total || page.items.isEmpty) {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<EmployeeLesson?>(
    future: _lesson,
    builder: (context, snapshot) {
      if (snapshot.data case final lesson? when lesson.playable) {
        return _VideoPlayer(courseId: widget.courseId, lesson: lesson);
      }
      return Theme(
        data: EmployeeStyles.theme(Theme.of(context)),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Aula'),
            leading: IconButton(
              tooltip: 'Voltar',
              icon: const SvgIcon(AppIcons.arrowBack),
              onPressed: () => leaveManagementPage(
                context,
                '/funcionario/course/${widget.courseId}',
              ),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: snapshot.connectionState != ConnectionState.done
                ? const LinearProgressIndicator()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Aula indisponível. Verifique seu perfil e o acesso ao curso.',
                      ),
                      TextButton(
                        onPressed: () => setState(() => _lesson = _load()),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}

class _VideoPlayer extends ConsumerStatefulWidget {
  final String courseId;
  final EmployeeLesson lesson;
  const _VideoPlayer({required this.courseId, required this.lesson});
  @override
  ConsumerState<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends ConsumerState<_VideoPlayer>
    with WidgetsBindingObserver {
  late final YoutubePlayerController _controller;
  late final PlaybackProgress _progress;
  StreamSubscription<YoutubeVideoState>? _positions;
  StreamSubscription<YoutubePlayerValue>? _states;
  String? _error;
  String? _playbackError;
  bool _leaving = false, _allowPop = false;
  bool _started = false;
  Duration _duration = Duration.zero;
  bool _loadingDuration = false;
  int _durationAttempts = 0, _retryDurationAt = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final scope = ref.read(employeeScopeProvider);
    _progress = PlaybackProgress(
      repository: ref.read(progressRepositoryProvider),
      companyId: scope.companyId,
      lessonId: widget.lesson.id,
      positionSec: widget.lesson.positionSec,
      completed: widget.lesson.completed,
      isCurrent: () => mounted && ref.read(employeeScopeProvider) == scope,
    );
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.lesson.videoId!,
      startSeconds: widget.lesson.positionSec.toDouble(),
      autoPlay: false,
      params: const YoutubePlayerParams(
        interfaceLanguage: 'pt',
        captionLanguage: 'pt',
        strictRelatedVideos: true,
      ),
    );
    _positions = _controller.videoStateStream.listen((state) {
      if (!_started) return;
      if (_controller.metadata.duration > Duration.zero) {
        _duration = _controller.metadata.duration;
      }
      if (_duration == Duration.zero &&
          state.position.inSeconds >= _retryDurationAt) {
        _retryDurationAt = state.position.inSeconds + 2;
        unawaited(_ensureDuration());
      }
      _progress.update(state.position, _duration);
      if (_progress.needsCheckpoint) unawaited(_checkpoint());
    });
    _states = _controller.listen((value) {
      if (value.playerState == PlayerState.playing) {
        _started = true;
        unawaited(_ensureDuration());
      }
      if (_started &&
          (value.playerState == PlayerState.paused ||
              value.playerState == PlayerState.ended)) {
        if (value.playerState == PlayerState.ended && _duration > Duration.zero) {
          _progress.update(_duration, _duration);
        }
        unawaited(_checkpoint(force: true));
      }
      if (value.hasError && mounted) {
        setState(
          () => _playbackError =
              'O YouTube não está disponível. Verifique a conexão e a liberação do YouTube na rede.',
        );
      }
    });
  }

  Future<void> _ensureDuration() async {
    if (_loadingDuration ||
        _duration > Duration.zero ||
        _durationAttempts >= 3) {
      return;
    }
    _loadingDuration = true;
    _durationAttempts++;
    try {
      final seconds = await _controller.duration.timeout(
        const Duration(seconds: 5),
      );
      if (seconds > 0) {
        _duration = Duration(milliseconds: (seconds * 1000).round());
        if (mounted && !_controller.value.hasError) {
          setState(() => _playbackError = null);
        }
      }
    } catch (_) {
      /* Playback events can retry; no backend polling is introduced. */
    } finally {
      _loadingDuration = false;
      if (_duration == Duration.zero &&
          _durationAttempts >= 3 &&
          mounted &&
          !_controller.value.hasError) {
        setState(
          () => _playbackError =
              'Não foi possível obter a duração. Recarregue o vídeo para validar a conclusão.',
        );
      }
    }
  }

  Future<void> _checkpoint({bool force = false}) async {
    if (!_started || _leaving) return;
    try {
      await _progress.save(force: force);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível salvar o progresso. Tente novamente antes de sair.',
        );
      }
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      unawaited(_controller.pauseVideo());
      if (_started) await _progress.save(force: true);
      if (!mounted) return;
      if (_started && _progress.completed) {
        try {
          await ref
              .read(employeeLearningRepositoryProvider)
              .issueCertificate(_progress.companyId, widget.courseId)
              .timeout(const Duration(seconds: 15));
        } on CourseIncompleteException {
          /* Other lessons still need to be completed. */
        } catch (_) {
          if (mounted) {
            employeeMessage(
              context,
              'Progresso salvo. Se o curso estiver concluído, tente emitir o certificado nos detalhes.',
            );
          }
        }
      }
      if (!mounted) return;
      refreshLearning(ref);
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        leaveManagementPage(context, '/funcionario/course/${widget.courseId}');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _leaving = false;
          _error =
              'Não foi possível salvar. Tente novamente ou saia sem salvar.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_checkpoint(force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positions?.cancel();
    _states?.cancel();
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: EmployeeStyles.theme(Theme.of(context)),
    child: PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.lesson.title),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _leaving ? null : _leave,
            icon: const SvgIcon(AppIcons.arrowBack),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            YoutubePlayer(controller: _controller),
            const SizedBox(height: 16),
            Text(
              _progress.completed
                  ? 'Aula concluída.'
                  : 'Assista a pelo menos 90% do vídeo para concluir a aula.',
            ),
            if (_playbackError != null) ...[
              const SizedBox(height: 16),
              Text(_playbackError!),
              TextButton(
                onPressed: () {
                  _started = false;
                  _durationAttempts = 0;
                  _retryDurationAt = 0;
                  unawaited(
                    _controller.loadVideoById(
                      videoId: widget.lesson.videoId!,
                      startSeconds: _progress.positionSec.toDouble(),
                    ),
                  );
                },
                child: const Text('Recarregar vídeo'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!),
              TextButton(
                onPressed: () => _checkpoint(force: true),
                child: const Text('Tentar salvar novamente'),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _allowPop = true);
                  leaveManagementPage(
                    context,
                    '/funcionario/course/${widget.courseId}',
                  );
                },
                child: const Text('Sair sem salvar'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _leaving ? null : _leave,
              child: Text(_leaving ? 'Salvando...' : 'Salvar e voltar'),
            ),
          ],
        ),
      ),
    ),
  );
}
