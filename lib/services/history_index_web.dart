import 'dart:js_interop';

bool get historyIndexEncryptedAtRest => false;

@JS('sendHistoryIndexCall')
external JSPromise<JSAny?> _request(
  JSString account,
  JSString operation,
  JSAny? args,
);

class HistoryStore {
  String get openStage => 'browser-store';
  String failureCode(Object error) => error.runtimeType.toString();
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
  Future<String?> loadScope() async => await _call('scope') as String?;
  Future<void> setScope(String scope, Set<String> allowedRooms) async =>
      _call('setScope', {'scope': scope, 'rooms': allowedRooms.toList()});
  Future<void> put(
    List<Map<String, Object?>> rows,
    bool text,
    int limit,
  ) async => _call('put', {'rows': rows, 'text': text, 'limit': limit});
  Future<bool> putArchive(
    List<Map<String, Object?>> rows,
    bool text,
    int limit,
  ) async =>
      await _call('put', {
        'rows': rows,
        'text': text,
        'limit': limit,
        'preserve': true,
      }) ==
      true;
  Future<Map<String, Object?>?> loadDownloadState() async {
    final value = await _call('downloadState');
    return value == null ? null : Map<String, Object?>.from(value as Map);
  }

  Future<void> saveDownloadState(Map<String, Object?>? value) async =>
      _call('saveDownloadState', {'state': value});
  Future<List<Map<String, Object?>>> readRows(List<String> ids) async =>
      (await _call('rows', {'ids': ids}) as List)
          .map((value) => Map<String, Object?>.from(value as Map))
          .toList();
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
  Future<void> acknowledgeWarning() async => _call('ackWarning');
  Future<String?> revision(String id) async =>
      await _call('revision', {'id': id}) as String?;
  Future<void> close() async => _call('close');
}
