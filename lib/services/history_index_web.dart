import 'dart:js_interop';

@JS('sendHistoryIndexCall')
external JSPromise<JSAny?> _request(
  JSString account,
  JSString operation,
  JSAny? args,
);

class HistoryStore {
  HistoryStore(this.account);
  final String account;
  Future<dynamic> _call(String op, [Object? args]) async =>
      (await _request(account.toJS, op.toJS, args.jsify()).toDart)?.dartify();
  Future<void> open() async {
    await _call('open');
  }

  Future<Map<String, Object?>> settings() async {
    final raw = Map<String, Object?>.from(await _call('settings') as Map);
    if (raw['limit'] is num) raw['limit'] = (raw['limit'] as num).toInt();
    return raw;
  }

  Future<void> configure(bool enabled, int limit) async =>
      _call('configure', {'enabled': enabled, 'limit': limit});
  Future<void> put(
    List<Map<String, Object?>> rows,
    bool text,
    int limit,
  ) async => _call('put', {'rows': rows, 'text': text, 'limit': limit});
  Future<List<String>> query(
    String room, {
    required List<String> terms,
    String? kind,
    String? sender,
    int? before,
    int? after,
    required int offset,
    required int limit,
  }) async =>
      (await _call('query', {
                'room': room,
                'terms': terms,
                'kind': kind,
                'sender': sender,
                'before': before,
                'after': after,
                'offset': offset,
                'limit': limit,
              })
              as List)
          .cast<String>();
  Future<Map<String, int>> stats() async => (await _call('stats') as Map).map(
    (key, value) => MapEntry(key as String, (value as num).toInt()),
  );
  Future<void> clear() async => _call('clear');
  Future<String?> revision(String id) async =>
      await _call('revision', {'id': id}) as String?;
  Future<void> close() async => _call('close');
}
