import 'dart:async';

enum PushStatus {
  unsupported,
  unconfigured,
  signedOut,
  contextRequired,
  loading,
  disabled,
  permission,
  denied,
  enabled,
  error,
}

enum PushPermission { granted, denied, undecided }

abstract interface class PushTransport {
  Future<bool> supported();
  Future<PushPermission> permission();
  Future<PushPermission> requestPermission();
  Future<String?> token();
  Future<void> deleteToken();
  Stream<String> get rotations;
}

abstract interface class PushStoreFactory {
  PushStore? capture(String userId);
}

abstract interface class PushStore {
  Future<bool> enabled(String userId);
  Future<void> setEnabled(bool value);
  Future<void> register(String token, String platform);
  Future<void> unregister(String token);
}

/// Serializes all token mutations; intent changes invalidate in-flight operations.
class PushLifecycle {
  PushLifecycle({
    required this.transport,
    required this.store,
    required this.platform,
    required this.configured,
    required this.platformSupported,
    required this.onStatus,
  });
  final PushTransport transport;
  final PushStoreFactory store;
  PushStore? _ownerStore;
  final String platform;
  final bool configured;
  final bool platformSupported;
  final void Function(PushStatus) onStatus;
  String? _user;
  bool _contextAvailable = false;
  String? _token;
  PushStore? _tokenStore;
  StreamSubscription<String>? _rotation;
  Future<void> _tail = Future.value();
  int _epoch = 0;
  bool _disposed = false;
  bool get _ready => configured && platformSupported;
  void _status(PushStatus status) {
    if (!_disposed) onStatus(status);
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> _enqueue(Future<void> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> _clear() async {
    await _rotation?.cancel();
    _rotation = null;
    final token = _token;
    final owner = _tokenStore;
    _token = null;
    _tokenStore = null;
    if (token != null && owner != null) {
      try {
        await owner.unregister(token);
      } catch (_) {}
    }
    try {
      await transport.deleteToken();
    } catch (_) {}
  }

  Future<void> switchUser(String? user, {bool contextAvailable = true}) {
    final epoch = ++_epoch;
    final old = _user;
    _user = user;
    _ownerStore = user == null || !_ready ? null : store.capture(user);
    _contextAvailable = contextAvailable;
    return _enqueue(() async {
      if (old != null && old != user) await _clear();
      if (!_current(epoch)) return;
      if (!platformSupported) {
        _status(PushStatus.unsupported);
        return;
      }
      if (!configured) {
        _status(PushStatus.unconfigured);
        return;
      }
      if (user == null) {
        _status(PushStatus.signedOut);
        return;
      }
      if (!_contextAvailable) {
        _status(PushStatus.contextRequired);
        return;
      }
      await _sync(epoch, user);
    });
  }

  Future<void> setContextAvailable(bool available) {
    final epoch = ++_epoch;
    _contextAvailable = available;
    return _enqueue(() async {
      if (!_current(epoch) || _user == null) return;
      if (!available) {
        _status(PushStatus.contextRequired);
        return;
      }
      if (_ready) await _sync(epoch, _user!);
    });
  }

  Future<void> _sync(int epoch, String user) async {
    _status(PushStatus.loading);
    final owner = store.capture(user);
    if (owner == null) {
      _status(PushStatus.error);
      return;
    }
    _ownerStore = owner;
    try {
      if (!await owner.enabled(user)) {
        if (_current(epoch)) {
          await _clear();
          if (_current(epoch)) _status(PushStatus.disabled);
        }
        return;
      }
      if (!_current(epoch)) return;
      if (!await transport.supported()) {
        if (_current(epoch)) _status(PushStatus.unsupported);
        return;
      }
      final permission = await transport.permission();
      if (!_current(epoch)) return;
      if (permission != PushPermission.granted) {
        await _clear();
        if (!_current(epoch)) return;
        _status(
          permission == PushPermission.denied
              ? PushStatus.denied
              : PushStatus.permission,
        );
        return;
      }
      await _register(epoch);
    } catch (_) {
      if (_current(epoch)) _status(PushStatus.error);
    }
  }

  Future<void> _register(int epoch, [String? rotated]) async {
    final owner = _ownerStore;
    if (owner == null) throw StateError('No authenticated owner');
    final token = rotated ?? await transport.token();
    if (!_current(epoch)) return;
    if (token == null || token.isEmpty) {
      _status(PushStatus.error);
      return;
    }
    if (_token != null && _token != token) {
      await _tokenStore?.unregister(_token!);
      _token = null;
      _tokenStore = null;
      if (!_current(epoch)) return;
    }
    // Remember the owning credential before the request: a network failure can
    // occur after the server has committed the registration.
    _token = token;
    _tokenStore = owner;
    if (!_current(epoch)) {
      await _clear();
      return;
    }
    try {
      await owner.register(token, platform);
    } catch (_) {
      await _clear();
      rethrow;
    }
    if (!_current(epoch)) {
      await _clear();
      return;
    }
    _rotation ??= transport.rotations.listen((token) {
      final eventEpoch = _epoch;
      unawaited(
        _enqueue(() async {
          if (!_current(eventEpoch) || _user == null || !_contextAvailable) {
            return;
          }
          try {
            final owner = _ownerStore;
            if (owner == null || !await owner.enabled(_user!)) {
              await _clear();
              if (_current(eventEpoch)) _status(PushStatus.disabled);
              return;
            }
            if (!_current(eventEpoch)) return;
            final permission = await transport.permission();
            if (!_current(eventEpoch)) return;
            if (permission != PushPermission.granted) {
              await _clear();
              if (_current(eventEpoch)) {
                _status(
                  permission == PushPermission.denied
                      ? PushStatus.denied
                      : PushStatus.permission,
                );
              }
              return;
            }
            await _register(eventEpoch, token);
          } catch (_) {
            if (_current(eventEpoch)) _status(PushStatus.error);
          }
        }),
      );
    });
    _status(PushStatus.enabled);
  }

  Future<void> enable() {
    if (!_ready || _user == null || !_contextAvailable) return Future.value();
    final epoch = ++_epoch;
    return _enqueue(() async {
      if (!_current(epoch)) return;
      _status(PushStatus.loading);
      try {
        if (!await transport.supported()) {
          if (_current(epoch)) _status(PushStatus.unsupported);
          return;
        }
        final permission = await transport.requestPermission();
        if (!_current(epoch)) return;
        if (permission != PushPermission.granted) {
          _status(
            permission == PushPermission.denied
                ? PushStatus.denied
                : PushStatus.permission,
          );
          return;
        }
        final owner = store.capture(_user!);
        if (owner == null) throw StateError('No authenticated owner');
        _ownerStore = owner;
        await owner.setEnabled(true);
        if (_current(epoch)) await _register(epoch);
      } catch (_) {
        if (_current(epoch)) _status(PushStatus.error);
      }
    });
  }

  Future<void> disable() {
    if (!_ready || _user == null) return Future.value();
    final epoch = ++_epoch;
    return _enqueue(() async {
      if (!_current(epoch)) return;
      _status(PushStatus.loading);
      try {
        final owner = store.capture(_user!);
        if (owner == null) throw StateError('No authenticated owner');
        await owner.setEnabled(false);
        await _clear();
        if (_current(epoch)) _status(PushStatus.disabled);
      } catch (_) {
        if (_current(epoch)) _status(PushStatus.error);
      }
    });
  }

  Future<void> refresh() {
    final user = _user;
    if (!_ready || user == null || !_contextAvailable) return Future.value();
    final epoch = ++_epoch;
    return _enqueue(() async {
      if (_current(epoch)) await _sync(epoch, user);
    });
  }

  Future<void> beforeLogout() {
    ++_epoch;
    return _enqueue(_clear);
  }

  void dispose() {
    _disposed = true;
    ++_epoch;
    unawaited(_rotation?.cancel());
  }
}
