import 'recovery_intent_stub.dart'
    if (dart.library.js_interop) 'recovery_intent_web.dart'
    as platform;

/// UI intent only, bound to an Auth-verified session ID; never a bearer token.
class RecoveryIntentStore {
  String? _memory;

  String? read() {
    try {
      return platform.read() ?? _memory;
    } catch (_) {
      return _memory;
    }
  }

  void save(String sessionId) {
    _memory = sessionId;
    try {
      platform.save(sessionId);
    } catch (_) {}
  }

  void clear() {
    _memory = null;
    try {
      platform.clear();
    } catch (_) {}
  }
}
