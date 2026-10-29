import 'dart:js_interop';

@JS('sendBrowserStorageInfo')
external JSPromise<JSAny?> _info(JSBoolean persist);
Future<Map<String, Object?>> browserStorageInfo({bool persist = false}) async =>
    Map<String, Object?>.from(
      (await _info(persist.toJS).toDart)?.dartify() as Map,
    );
