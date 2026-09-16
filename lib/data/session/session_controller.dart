import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

/// Listenable that tells [GoRouter] to re-evaluate its redirect when the
/// session changes (login/logout).
final sessionRefresh = SessionRefreshNotifier();

class SessionRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class SessionController extends Notifier<AppSession?> {
  @override
  AppSession? build() => null;

  void login(AppSession session) {
    state = session;
    sessionRefresh.refresh();
  }

  void logout() {
    state = null;
    sessionRefresh.refresh();
  }
}

final sessionProvider =
    NotifierProvider<SessionController, AppSession?>(SessionController.new);
