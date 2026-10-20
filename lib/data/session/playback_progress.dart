import '../repositories/repositories.dart';

class PlaybackProgress {
  final ProgressRepository repository;
  final String companyId, lessonId;
  final bool Function() isCurrent;
  int positionSec;
  bool completed;
  int _savedPosition;
  bool _savedCompleted;
  Future<void>? _saving;
  PlaybackProgress({
    required this.repository,
    required this.companyId,
    required this.lessonId,
    required this.isCurrent,
    required this.positionSec,
    required this.completed,
  }) : _savedPosition = positionSec,
       _savedCompleted = completed;

  void update(Duration position, Duration duration) {
    if (duration.inMilliseconds <= 0) {
      if (position > Duration.zero) positionSec = position.inSeconds;
      return;
    }
    positionSec = position.inSeconds < 0 ? 0 : position.inSeconds;
    if (duration.inMilliseconds > 0 &&
        position.inMilliseconds / duration.inMilliseconds >= 0.9) {
      completed = true;
    }
  }

  bool get needsCheckpoint =>
      (positionSec - _savedPosition).abs() >= 15 ||
      completed != _savedCompleted;
  Future<void> save({bool force = false}) async {
    while (_saving != null) {
      await _saving!;
    }
    if (!isCurrent()) {
      throw StateError('O perfil mudou. Reabra a aula no perfil correto.');
    }
    if (!force && !needsCheckpoint) return;
    final position = positionSec;
    final done = completed;
    final pending = repository.save(
      companyId,
      lessonId,
      positionSec: position,
      completed: done,
    );
    _saving = pending;
    try {
      await pending;
      _savedPosition = position;
      _savedCompleted = done;
    } finally {
      if (identical(_saving, pending)) _saving = null;
    }
  }
}
