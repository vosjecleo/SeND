import 'dart:js_interop';

@JS('sendVaultBind')
external JSPromise<JSString> _bind(JSString dataset, JSString? expected);
@JS('sendVaultHash')
external JSPromise<JSString> _hash(
  JSString dataset,
  JSString store,
  JSString key,
);
@JS('sendVaultSeal')
external JSPromise<JSAny?> _seal(
  JSString dataset,
  JSString store,
  JSString key,
  JSAny? value,
);
@JS('sendVaultOpen')
external JSPromise<JSAny?> _open(
  JSString dataset,
  JSString store,
  JSString key,
  JSAny? value,
);

class WebRecordVault {
  const WebRecordVault(this.dataset);
  final String dataset;
  Future<String> bind(String? expected) async =>
      (await _bind(dataset.toJS, expected?.toJS).toDart).toDart;
  Future<String> hash(String store, String key) async =>
      (await _hash(dataset.toJS, store.toJS, key.toJS).toDart).toDart;
  Future<JSAny?> seal(String store, String key, Object? value) async =>
      _seal(dataset.toJS, store.toJS, key.toJS, value.jsify()).toDart;
  Future<Object?> open(String store, String key, JSAny? value) async =>
      (await _open(
        dataset.toJS,
        store.toJS,
        key.toJS,
        value,
      ).toDart)?.dartify();
}
