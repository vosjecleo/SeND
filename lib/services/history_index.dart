import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'history_index_native.dart'
    if (dart.library.js_interop) 'history_index_web.dart'
    as platform;

class HistoryIndex extends ChangeNotifier {
  HistoryIndex(this.account);
  final String account;
  late final platform.HistoryStore _store;
  bool enabled = false, prompted = false, ready = false;
  int limitMiB = 50, bytes = 0, entries = 0;
  Future<void> _queue = Future.value();
  bool _closed = false;
  Future<T> _serial<T>(Future<T> Function() operation) {
    if (_closed) return Future.error(StateError('Index closed'));
    final result = _queue.catchError((Object _) {}).then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> open() async {
    _store = platform.HistoryStore(
      sha256.convert(utf8.encode(account)).toString(),
    );
    await _store.open();
    final settings = await _store.settings();
    enabled = settings['enabled'] == true;
    prompted = settings['prompted'] == true;
    limitMiB = (settings['limit'] as int? ?? 50).clamp(16, 250);
    ready = true;
    await refreshStats();
  }

  Future<void> configure({required bool text, int? limit}) => _serial(() async {
    final budget = (limit ?? limitMiB).clamp(16, 250);
    await _store.configure(text, budget);
    enabled = text;
    prompted = true;
    limitMiB = budget;
    await refreshStats();
  });

  Future<void> ingest(List<Map<String, Object?>> rows) {
    final copy = rows
        .map((r) => {...r, 'body': enabled ? r['body'] : ''})
        .toList();
    return _serial(() async {
      await _store.put(copy, enabled, limitMiB);
      await refreshStats();
    });
  }

  Future<List<String>> query(
    String room, {
    List<String> terms = const [],
    String? kind,
    String? sender,
    int? before,
    int? after,
    int offset = 0,
    int limit = 50,
  }) => _serial(
    () => _store.query(
      room,
      terms: terms,
      kind: kind,
      sender: sender,
      before: before,
      after: after,
      offset: offset,
      limit: limit,
    ),
  );

  Future<void> clear() => _serial(() async {
    await _store.clear();
    await refreshStats();
  });
  Future<String?> revision(String id) => _serial(() => _store.revision(id));

  Future<void> refreshStats() async {
    final stats = await _store.stats();
    bytes = stats['bytes'] ?? 0;
    entries = stats['entries'] ?? 0;
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _queue.catchError((Object _) {});
    try {
      await _store.close();
    } catch (_) {
      /* Failed opens may have no store. */
    }
    dispose();
  }
}
