import 'dart:js_interop';
import 'dart:async';
import 'package:web/web.dart' as web;

@JS('deltieBrowserStart')
external JSPromise<JSBoolean> _start();
@JS('deltieSubscribePush')
external JSPromise<JSString> _subscribe();
@JS('deltieClearNotifications')
external JSPromise<JSAny?> _clear(JSString roomId);
@JS('deltieDisablePush')
external JSPromise<JSAny?> _disable();
@JS('deltiePushLease')
external void _lease(JSString key);
@JS('deltiePushDiagnostics')
external JSPromise<JSString> _diagnostics();
@JS('deltieTestPush')
external JSPromise<JSAny?> _testPush();
@JS('sendWritePushPreview')
external JSPromise<JSAny?> _writePreview(JSString? json);
@JS('sendConfigurePresence')
external void _configurePresence(JSString? json);
@JS('sendPublishPresence')
external JSPromise<JSAny?> _publishPresence();
@JS('sendKeyboardVisible')
external JSBoolean? _keyboardVisible();
@JS('sendKeyboardGeometry')
external JSFunction? get _keyboardGeometryFunction;

void configureBrowserPresence(String? json) => _configurePresence(json?.toJS);
Future<void> publishBrowserPresence() async {
  await _publishPresence().toDart;
}

bool? get browserKeyboardVisible => _keyboardVisible()?.toDart;
Map<String, Object?>? get browserKeyboardGeometry {
  final value = _keyboardGeometryFunction?.callAsFunction()?.dartify();
  return value is Map ? Map<String, Object?>.from(value) : null;
}

Stream<Map<String, Object?>> get browserKeyboardGeometryChanges {
  late StreamController<Map<String, Object?>> controller;
  final changed = ((web.Event _) {
    final geometry = browserKeyboardGeometry;
    if (geometry != null) controller.add(geometry);
  }).toJS;
  controller = StreamController(
    onListen: () =>
        web.window.addEventListener('send-keyboard-geometry', changed),
    onCancel: () =>
        web.window.removeEventListener('send-keyboard-geometry', changed),
  );
  return controller.stream;
}

bool _pageHidden = false;
bool get browserApplicationVisible => !_pageHidden && !web.document.hidden;
Stream<bool> get browserVisibilityChanges {
  late StreamController<bool> controller;
  final changed = ((web.Event _) {
    if (!web.document.hidden) _pageHidden = false;
    controller.add(browserApplicationVisible);
  }).toJS;
  final hidden = ((web.Event _) {
    _pageHidden = true;
    controller.add(false);
  }).toJS;
  final shown = ((web.Event _) {
    _pageHidden = false;
    controller.add(browserApplicationVisible);
  }).toJS;
  controller = StreamController(
    onListen: () {
      _pageHidden = web.document.hidden;
      web.document.addEventListener('visibilitychange', changed);
      web.window.addEventListener('pagehide', hidden);
      web.window.addEventListener('pageshow', shown);
    },
    onCancel: () {
      web.document.removeEventListener('visibilitychange', changed);
      web.window.removeEventListener('pagehide', hidden);
      web.window.removeEventListener('pageshow', shown);
    },
  );
  return controller.stream;
}

Future<void> writeBrowserPushPreview(String? json) async {
  await _writePreview(json?.toJS).toDart;
}

Future<String> browserPushDiagnostics() async =>
    (await _diagnostics().toDart).toDart;
Future<void> testBrowserPush() async {
  await _testPush().toDart;
}

Future<bool> initializeBrowser() async => (await _start().toDart).toDart;
Future<String> subscribeBrowserPush() async =>
    (await _subscribe().toDart).toDart;
Future<void> clearBrowserNotifications(String roomId) async {
  await _clear(roomId.toJS).toDart;
}

Future<void> disableBrowserPush() async {
  await _disable().toDart;
}

void setBrowserPushLease(String key) => _lease(key.toJS);
Stream<Map<String, String>> get browserNotificationClicks {
  late StreamController<Map<String, String>> controller;
  final listener = ((web.MessageEvent event) {
    if (event.origin != web.window.location.origin) return;
    final data = event.data.dartify();
    if (data is! Map || data['type'] != 'deltiecord-open-room') return;
    final room = data['room_id'];
    if (room is! String || room.length > 1024) return;
    controller.add({'room_id': room, 'event_id': '${data['event_id'] ?? ''}'});
  }).toJS;
  controller = StreamController(
    onListen: () => web.window.navigator.serviceWorker.addEventListener(
      'message',
      listener,
    ),
    onCancel: () => web.window.navigator.serviceWorker.removeEventListener(
      'message',
      listener,
    ),
  );
  return controller.stream;
}
