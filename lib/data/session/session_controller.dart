import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';

final sessionRefresh = SessionRefreshNotifier();

class SessionRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class SessionController extends AsyncNotifier<AppSession?> {
  @override
  Future<AppSession?> build() async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isNotEmpty && key.isNotEmpty) {
      final subscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((event) {
            if (event.event == AuthChangeEvent.signedOut) {
              state = const AsyncData(null);
              sessionRefresh.refresh();
            } else if (event.event == AuthChangeEvent.signedIn ||
                event.event == AuthChangeEvent.tokenRefreshed) {
              unawaited(_sync());
            }
          });
      ref.onDispose(subscription.cancel);
    }
    final result = await ref.read(authRepositoryProvider).current();
    return result;
  }

  Future<void> _sync() async {
    try {
      await reload();
    } catch (error, stack) {
      state = AsyncError(error, stack);
      sessionRefresh.refresh();
    }
  }

  Future<AppSession> login({
    required String email,
    required String password,
  }) async {
    final session = await ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
    state = AsyncData(session);
    sessionRefresh.refresh();
    return session;
  }

  Future<AppSession?> reload() async {
    final session = await ref.read(authRepositoryProvider).current();
    state = AsyncData(session);
    sessionRefresh.refresh();
    return session;
  }

  Future<void> select(AccessContext context) async {
    await ref.read(authRepositoryProvider).selectContext(context);
    final session = state.value;
    if (session == null) return;
    state = AsyncData(
      AppSession(
        user: session.user,
        contexts: session.contexts,
        active: context,
        needsPassword: session.needsPassword,
      ),
    );
    sessionRefresh.refresh();
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
    sessionRefresh.refresh();
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, AppSession?>(
  SessionController.new,
);
