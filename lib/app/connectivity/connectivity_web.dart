import 'dart:async';
import 'dart:js_interop';

@JS('navigator.onLine')
external bool get _online;

@JS('window.addEventListener')
external void _addListener(String type, JSFunction listener);

@JS('window.removeEventListener')
external void _removeListener(String type, JSFunction listener);

bool get isOffline => !_online;

Stream<bool> offlineChanges() {
  late final StreamController<bool> controller;
  final listener = ((JSAny? event) => controller.add(isOffline)).toJS;
  controller = StreamController<bool>(
    onListen: () {
      _addListener('online', listener);
      _addListener('offline', listener);
      controller.add(isOffline);
    },
    onCancel: () {
      _removeListener('online', listener);
      _removeListener('offline', listener);
    },
  );
  return controller.stream;
}
