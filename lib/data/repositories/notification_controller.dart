import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../session/session_controller.dart';
import 'notification_repository.dart';

const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _vapid = String.fromEnvironment('VAPID_PUBLIC_KEY');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get notificationConfigured =>
    _apiKey.isNotEmpty &&
    _appId.isNotEmpty &&
    _senderId.isNotEmpty &&
    _projectId.isNotEmpty &&
    (!kIsWeb || _vapid.isNotEmpty);
bool get notificationPlatformSupported =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.android;

enum PushStatus {
  unsupported,
  unconfigured,
  signedOut,
  loading,
  disabled,
  permission,
  denied,
  enabled,
  error,
}

class NotificationController extends Notifier<PushStatus> {
  String? _user;
  String? _token;
  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  final events = StreamController<bool>.broadcast();
  int _generation = 0;
  NotificationRepository get _repo =>
      NotificationRepository(Supabase.instance.client);
  String get _platform => kIsWeb ? 'web' : 'android';

  @override
  PushStatus build() {
    ref.listen(sessionProvider, (_, next) {
      final id = next.value?.user.id;
      if (id != _user) {
        unawaited(_switchUser(id));
      }
    }, fireImmediately: true);
    ref.onDispose(() {
      _generation++;
      _refresh?.cancel();
      _foreground?.cancel();
      _opened?.cancel();
      events.close();
    });
    if (!notificationPlatformSupported) return PushStatus.unsupported;
    if (!notificationConfigured ||
        _supabaseUrl.isEmpty ||
        _supabaseKey.isEmpty) {
      return PushStatus.unconfigured;
    }
    return ref.read(sessionProvider).value == null
        ? PushStatus.signedOut
        : PushStatus.loading;
  }

  Future<void> _switchUser(String? id) async {
    final generation = ++_generation;
    final previousUser = _user;
    _user = id;
    _token = null;
    await _refresh?.cancel();
    _refresh = null;
    if (previousUser != null && previousUser != id) {
      try {
        // ignore: deprecated_member_use
        await _messaging?.deleteToken();
      } catch (_) {}
    }
    if (generation != _generation) return;
    if (!notificationPlatformSupported) {
      state = PushStatus.unsupported;
      return;
    }
    if (!notificationConfigured ||
        _supabaseUrl.isEmpty ||
        _supabaseKey.isEmpty) {
      state = PushStatus.unconfigured;
      return;
    }
    if (id == null) {
      // The previous JWT may already be gone. Delete the local installation token;
      // registration by another user is additionally exclusive on the server.
      try {
        // ignore: deprecated_member_use
        await _messaging?.deleteToken();
      } catch (_) {}
      if (generation == _generation) state = PushStatus.signedOut;
      return;
    }
    state = PushStatus.loading;
    try {
      if (!await _repo.enabled(id)) {
        if (generation == _generation) state = PushStatus.disabled;
        return;
      }
      if (generation != _generation) return;
      _messaging ??= await _initMessaging();
      final messaging = _messaging!;
      if (!await messaging.isSupported()) {
        if (generation == _generation) state = PushStatus.unsupported;
        return;
      }
      final permission =
          (await messaging.getNotificationSettings()).authorizationStatus;
      if (generation != _generation) return;
      if (permission != AuthorizationStatus.authorized &&
          permission != AuthorizationStatus.provisional) {
        state = permission == AuthorizationStatus.denied
            ? PushStatus.denied
            : PushStatus.permission;
        return;
      }
      await _register(generation);
    } catch (_) {
      if (generation == _generation) state = PushStatus.error;
    }
  }

  Future<FirebaseMessaging> _initMessaging() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
    }
    _foreground ??= FirebaseMessaging.onMessage.listen(
      (_) => events.add(false),
    );
    _opened ??= FirebaseMessaging.onMessageOpenedApp.listen(
      (_) => events.add(true),
    );
    final messaging = FirebaseMessaging.instance;
    if (await messaging.getInitialMessage() != null) events.add(true);
    return messaging;
  }

  Future<void> _register(int generation) async {
    final params = Uri(
      queryParameters: {
        'apiKey': _apiKey,
        'appId': _appId,
        'messagingSenderId': _senderId,
        'projectId': _projectId,
      },
    ).query;
    // ignore: deprecated_member_use
    final token = await _messaging!.getToken(
      vapidKey: kIsWeb ? _vapid : null,
      serviceWorkerScriptPath: kIsWeb
          ? '/push/firebase-messaging-sw.js?$params'
          : null,
    );
    if (generation != _generation || token == null) return;
    await _repo.register(token, _platform);
    if (generation != _generation) {
      try {
        // A stale registration must never remain active after an identity change.
        await _messaging?.deleteToken(); // ignore: deprecated_member_use
      } catch (_) {}
      return;
    }
    _token = token;
    // ignore: deprecated_member_use
    _refresh = _messaging!.onTokenRefresh.listen((token) async {
      if (generation != _generation) return;
      try {
        await _repo.register(token, _platform);
        if (generation == _generation) _token = token;
      } catch (_) {
        if (generation == _generation) state = PushStatus.error;
      }
    });
    state = PushStatus.enabled;
  }

  Future<void> enable() async {
    final id = _user;
    if (id == null) return;
    final generation = ++_generation;
    state = PushStatus.loading;
    try {
      _messaging ??= await _initMessaging();
      if (!await _messaging!.isSupported()) {
        if (generation == _generation) state = PushStatus.unsupported;
        return;
      }
      final permission =
          (await _messaging!.requestPermission()).authorizationStatus;
      if (generation != _generation) return;
      if (permission != AuthorizationStatus.authorized &&
          permission != AuthorizationStatus.provisional) {
        state = PushStatus.denied;
        return;
      }
      await _repo.setEnabled(true);
      if (generation == _generation) await _register(generation);
    } catch (_) {
      if (generation == _generation) state = PushStatus.error;
    }
  }

  Future<void> disable() async {
    ++_generation;
    state = PushStatus.loading;
    try {
      await _repo.setEnabled(false);
      await _refresh?.cancel();
      _refresh = null;
      if (_token != null) await _repo.unregister(_token!);
      // ignore: deprecated_member_use
      await _messaging?.deleteToken();
      _token = null;
      state = PushStatus.disabled;
    } catch (_) {
      state = PushStatus.error;
    }
  }

  Future<void> beforeLogout() async {
    ++_generation;
    await _refresh?.cancel();
    _refresh = null;
    try {
      if (_token != null) await _repo.unregister(_token!);
    } catch (_) {}
    try {
      // ignore: deprecated_member_use
      await _messaging?.deleteToken();
    } catch (_) {}
    _token = null;
  }
}

final notificationControllerProvider =
    NotifierProvider<NotificationController, PushStatus>(
      NotificationController.new,
    );
