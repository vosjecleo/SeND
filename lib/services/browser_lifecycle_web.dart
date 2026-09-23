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
