import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../session/session_controller.dart';
import 'notification_repository.dart';
import 'push_lifecycle.dart';
export 'push_lifecycle.dart' show PushStatus;

const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _vapid = String.fromEnvironment('VAPID_PUBLIC_KEY');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool validFirebaseConfig({
  required String apiKey,
  required String appId,
  required String senderId,
  required String projectId,
  required String vapid,
  required bool web,
}) {
  final platform = web ? 'web' : 'android';
  return RegExp(r'^AIza[\w-]{35}$').hasMatch(apiKey) &&
      RegExp(r'^[0-9]{5,20}$').hasMatch(senderId) &&
      RegExp(
        '^1:${RegExp.escape(senderId)}:$platform:[a-fA-F0-9]{10,64}'
        r'$',
      ).hasMatch(appId) &&
      RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(projectId) &&
      (!web || RegExp(r'^B[A-Za-z0-9_-]{86}$').hasMatch(vapid));
}

bool get notificationConfigured => validFirebaseConfig(
  apiKey: _apiKey,
  appId: _appId,
  senderId: _senderId,
  projectId: _projectId,
  vapid: _vapid,
  web: kIsWeb,
);
bool get notificationPlatformSupported =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.android;

class FirebasePushTransport implements PushTransport {
  FirebasePushTransport(this.events);
  final StreamController<bool> events;
  FirebaseMessaging? _messaging;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  Future<FirebaseMessaging> _init() async {
    if (_messaging != null) return _messaging!;
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
    _messaging = FirebaseMessaging.instance;
    if (await _messaging!.getInitialMessage() != null) events.add(true);
    return _messaging!;
  }

  PushPermission _convert(AuthorizationStatus value) => switch (value) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.denied => PushPermission.denied,
    _ => PushPermission.undecided,
  };
  @override
  Future<bool> supported() async => (await _init()).isSupported();
  @override
  Future<PushPermission> permission() async => _convert(
    (await (await _init()).getNotificationSettings()).authorizationStatus,
  );
  @override
  Future<PushPermission> requestPermission() async =>
      _convert((await (await _init()).requestPermission()).authorizationStatus);
  @override
  Future<String?> token() async {
    final params = Uri(
      queryParameters: {
        'apiKey': _apiKey,
        'appId': _appId,
        'messagingSenderId': _senderId,
        'projectId': _projectId,
      },
    ).query;
    // ignore: deprecated_member_use
    return (await _init()).getToken(
      vapidKey: kIsWeb ? _vapid : null,
      serviceWorkerScriptPath: kIsWeb
          ? '/push/firebase-messaging-sw.js?$params'
          : null,
    );
  }

  @override
  Future<void> deleteToken() async {
    // Never initialize Firebase solely for cleanup.
    // ignore: deprecated_member_use
    await _messaging?.deleteToken();
  }

  @override
  Stream<String> get rotations {
    // ignore: deprecated_member_use
    return _messaging!.onTokenRefresh;
  }

  void dispose() {
    _foreground?.cancel();
    _opened?.cancel();
  }
}

class NotificationController extends Notifier<PushStatus> {
  final events = StreamController<bool>.broadcast();
  late final PushLifecycle _lifecycle;
  String? _user;
  String? _contextKey;
  @override
  PushStatus build() {
    final transport = FirebasePushTransport(events);
    _lifecycle = PushLifecycle(
      transport: transport,
      store: _OwnerStoreFactory(),
      platform: kIsWeb ? 'web' : 'android',
      configured:
          notificationConfigured &&
          _supabaseUrl.isNotEmpty &&
          _supabaseKey.isNotEmpty,
      platformSupported: notificationPlatformSupported,
      onStatus: (value) => state = value,
    );
    ref.listen(sessionProvider, (_, next) {
      // Loading during a context/session refresh is not an identity change.
      if (next.isLoading || next.hasError) return;
      final session = next.value;
      final id = session?.user.id;
      final active = session?.active;
      final key = active == null
          ? null
          : '${active.role.name}:${active.companyId}';
      if (id != _user) {
        _user = id;
        _contextKey = key;
        unawaited(_lifecycle.switchUser(id, contextAvailable: key != null));
      } else if (key != _contextKey) {
        _contextKey = key;
        unawaited(_lifecycle.setContextAvailable(key != null));
      }
    }, fireImmediately: true);
    ref.onDispose(() {
      _lifecycle.dispose();
      transport.dispose();
      events.close();
    });
    if (!notificationPlatformSupported) return PushStatus.unsupported;
    if (!notificationConfigured ||
        _supabaseUrl.isEmpty ||
        _supabaseKey.isEmpty) {
      return PushStatus.unconfigured;
    }
    return PushStatus.signedOut;
  }

  Future<void> enable() => _lifecycle.enable();
  Future<void> disable() => _lifecycle.disable();
  Future<void> refresh() => _lifecycle.refresh();
  Future<void> beforeLogout() => _lifecycle.beforeLogout();
}

class _OwnerStoreFactory implements PushStoreFactory {
  @override
  PushStore? capture(String userId) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.user.id != userId) return null;
    final jwt = session.accessToken;
    return NotificationRepository(
      SupabaseClient(_supabaseUrl, _supabaseKey, accessToken: () async => jwt),
    );
  }
}

final notificationControllerProvider =
    NotifierProvider<NotificationController, PushStatus>(
      NotificationController.new,
    );
