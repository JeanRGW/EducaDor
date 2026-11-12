import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/pending_invite.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import '../repositories/notification_controller.dart';

final sessionRefresh = SessionRefreshNotifier();

class SessionRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class SessionController extends AsyncNotifier<AppSession?> {
  int _reloadEpoch = 0;
  @override
  Future<AppSession?> build() async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isNotEmpty && key.isNotEmpty) {
      final subscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((event) {
            if (event.event == AuthChangeEvent.signedOut) {
              _reloadEpoch++;
              ref.read(authRepositoryProvider).clearRecoverySession();
              state = const AsyncData(null);
              sessionRefresh.refresh();
            } else if (event.event == AuthChangeEvent.passwordRecovery) {
              ref.read(authRepositoryProvider).markRecoverySession();
              unawaited(_sync());
            } else if (event.event == AuthChangeEvent.signedIn ||
                event.event == AuthChangeEvent.tokenRefreshed ||
                event.event == AuthChangeEvent.mfaChallengeVerified) {
              unawaited(_sync());
            }
          });
      ref.onDispose(subscription.cancel);
    }
    final epoch = ++_reloadEpoch;
    try {
      final result = await ref.read(authRepositoryProvider).current();
      return epoch == _reloadEpoch ? result : state.value;
    } catch (_) {
      if (epoch != _reloadEpoch) return state.value;
      rethrow;
    }
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
    final epoch = ++_reloadEpoch;
    try {
      final session = await ref.read(authRepositoryProvider).current();
      if (epoch != _reloadEpoch) return state.value;
      state = AsyncData(session);
      sessionRefresh.refresh();
      return session;
    } catch (_) {
      if (epoch != _reloadEpoch) return state.value;
      rethrow;
    }
  }

  void discardContext(Role role, String? companyId) {
    final session = state.value;
    if (session == null) return;
    bool matches(AccessContext access) =>
        access.role == role && access.companyId == companyId;
    state = AsyncData(
      AppSession(
        user: session.user,
        contexts: session.contexts.where((access) => !matches(access)).toList(),
        active: session.active != null && matches(session.active!)
            ? null
            : session.active,
        needsPassword: session.needsPassword,
        needsMfa: session.needsMfa,
        recoveringPassword: session.recoveringPassword,
      ),
    );
    sessionRefresh.refresh();
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
        needsMfa: session.needsMfa,
        recoveringPassword: session.recoveringPassword,
      ),
    );
    sessionRefresh.refresh();
  }

  Future<void> logout() async {
    setPendingInvite(null);
    setPendingStartInvite(null);
    _reloadEpoch++;
    try {
      await ref.read(notificationControllerProvider.notifier).beforeLogout();
    } catch (_) {
      // Push cleanup must not prevent sign-out.
    }
    await ref.read(authRepositoryProvider).signOut();
    _reloadEpoch++;
    state = const AsyncData(null);
    sessionRefresh.refresh();
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, AppSession?>(
  SessionController.new,
);
