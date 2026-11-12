import 'package:web/web.dart' as web;

final _fallback = <String, String>{};
bool _storageFailed = false;

String? readStoredInvite(String key) {
  if (_storageFailed) return _fallback[key];
  try {
    return web.window.sessionStorage.getItem(key) ?? _fallback[key];
  } catch (_) {
    return _fallback[key];
  }
}

void writeStoredInvite(String key, String? value) {
  if (value == null) {
    _fallback.remove(key);
  } else {
    _fallback[key] = value;
  }
  if (_storageFailed) return;
  try {
    if (value == null) {
      web.window.sessionStorage.removeItem(key);
    } else {
      web.window.sessionStorage.setItem(key, value);
    }
  } catch (_) {
    _storageFailed = true;
    // Storage can be disabled; retain the invitation for this page lifetime.
  }
}
