import 'dart:js_interop';

@JS('sessionStorage.getItem')
external String? _getItem(String key);
@JS('sessionStorage.setItem')
external void _setItem(String key, String value);
@JS('sessionStorage.removeItem')
external void _removeItem(String key);

const _key = 'educador.password-recovery.session';
String? read() => _getItem(_key);
void save(String sessionId) => _setItem(_key, sessionId);
void clear() => _removeItem(_key);
