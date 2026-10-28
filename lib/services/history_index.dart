import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'history_index_limits.dart';
import 'history_scope.dart';
import 'history_index_native.dart'
    if (dart.library.js_interop) 'history_index_web.dart'
    as platform;

class HistoryIndex extends ChangeNotifier {
  HistoryIndex(this.account, {platform.HistoryStore? store})
    : _providedStore = store;
  final platform.HistoryStore? _providedStore;
  final String account;
  bool get encryptedAtRest => platform.historyIndexEncryptedAtRest;
  late final platform.HistoryStore _store;
  String _openStage = 'database';
  String get openStage =>
      _openStage == 'database' ? _store.openStage : _openStage;
  String failureCode(Object error) => _store.failureCode(error);
  bool enabled = false, prompted = false, ready = false;
  HistoryScope scope = HistoryScope.all;
  int limitMiB = 100, bytes = 0, entries = 0, budgetBytes = 0;
  bool warningPending = false;
  bool _warned = false, _closed = false;
  Future<void> _queue = Future.value();
  Timer? _ingestTimer;
  final _pending = <String, Map<String, Object?>>{};
  final _waiters = <Completer<void>>[];
  int get entryLimit => historyIndexEntryLimit(limitMiB);
  double get capacityRatio =>
      max(budgetBytes / (limitMiB * 1048576), entries / entryLimit);

  Future<T> _serial<T>(Future<T> Function() operation) {
    if (_closed) return Future.error(StateError('Index closed'));
    final result = _queue.catchError((Object _) {}).then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> open() async {
    _store =
        _providedStore ??
        platform.HistoryStore(sha256.convert(utf8.encode(account)).toString());
    await _store.open();
    _openStage = 'settings';
    final settings = await _store.settings();
    enabled = settings['enabled'] == true;
    prompted = settings['prompted'] == true;
    scope = HistoryScope.parse(await _store.loadScope());
    limitMiB = (settings['limit'] as int? ?? 100).clamp(16, historyIndexMaxMiB);
    if (!enabled && settings['limit'] == 50) {
      limitMiB = 100;
      await _store.configure(false, 100);
    }
    ready = true;
    _openStage = 'usage';
    await refreshStats();
  }

  Future<void> configure({required bool text, int? limit}) async {
    await flush();
    await _serial(() async {
      final budget = (limit ?? limitMiB).clamp(16, historyIndexMaxMiB);
      await _store.configure(text, budget);
      enabled = text;
      prompted = true;
      limitMiB = budget;
      await refreshStats(force: true);
    });
  }

  Future<void> ingest(List<Map<String, Object?>> rows) {
    if (_closed) return Future.value();
    for (final row in rows) {
      _pending[row['id'] as String] = {
        ...row,
        'body': enabled ? row['body'] : '',
      };
    }
    if (_pending.isEmpty) return Future.value();
    final waiter = Completer<void>();
    _waiters.add(waiter);
    _ingestTimer ??= Timer(const Duration(milliseconds: 100), () {
      unawaited(flush().catchError((Object _) {}));
    });
    if (_pending.length >= 256) unawaited(flush().catchError((Object _) {}));
    return waiter.future;
  }

  /// Called only after an explicit scope choice with a loaded room list.
  /// Removing local search entries never removes Matrix events or media.
  Future<void> setScope(HistoryScope value, Set<String> allowedRooms) async {
    await flush();
    await _serial(() async {
      await _store.setScope(value.name, allowedRooms);
      scope = value;
      await refreshStats(force: true);
    });
  }

  Future<void> flush() {
    _ingestTimer?.cancel();
    _ingestTimer = null;
    if (_pending.isEmpty) return _queue;
    final rows = _pending.values.toList(), waiters = List.of(_waiters);
    _pending.clear();
    _waiters.clear();
    final work = _serial(() async {
      // Recheck at admission: an event may have been prepared while the user
      // was changing scope, before the asynchronous write reached this queue.
      final admitted = rows.where((row) {
        if (row['deleted'] == true) return true;
        final kind = HistoryRoomKind.values
            .where((k) => k.name == row['room_kind'])
            .firstOrNull;
        return kind == null || scope.includes(kind);
      }).toList();
      await _store.put(admitted, enabled, limitMiB);
      await refreshStats();
    });
    unawaited(
      work.then<void>(
        (_) {
          for (final waiter in waiters) {
            waiter.complete();
          }
        },
        onError: (Object error, StackTrace stack) {
          for (final waiter in waiters) {
            waiter.completeError(error, stack);
          }
        },
      ),
    );
    return work;
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
  }) async {
    await flush();
    return _serial(
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
  }

  Future<String?> revision(String id) => _serial(() => _store.revision(id));
  Future<List<Map<String, Object?>>> readRows(List<String> ids) =>
      _serial(() => _store.readRows(ids));
  Future<Map<String, Object?>?> loadDownloadState() =>
      _serial(_store.loadDownloadState);
  Future<void> saveDownloadState(Map<String, Object?>? value) =>
      _serial(() => _store.saveDownloadState(value));

  Future<bool> appendArchive(List<Map<String, Object?>> rows) async {
    await flush();
    return _serial(() async {
      if (!enabled) {
        throw StateError('Enable text indexing before downloading history.');
      }
      final added = await _store.putArchive(rows, true, limitMiB);
      await refreshStats();
      return added;
    });
  }

  Future<void> clear() async {
    await flush();
    await _serial(() async {
      await _store.clear();
      await refreshStats(force: true);
    });
  }

  Future<void> acknowledgeCapacityWarning() => _serial(() async {
    await _store.acknowledgeWarning();
    _warned = true;
    warningPending = false;
    notifyListeners();
  });

  Future<void> refreshStats({bool force = false}) async {
    final stats = await _store.stats();
    final old = [bytes, entries, budgetBytes, warningPending];
    bytes = stats['bytes'] ?? 0;
    entries = stats['entries'] ?? 0;
    budgetBytes = stats['budgetBytes'] ?? bytes;
    _warned = stats['warning'] == 1;
    warningPending =
        enabled && !_warned && (stats['warning'] == 2 || capacityRatio >= .8);
    if (!_closed &&
        (force ||
            !listEquals(old, [bytes, entries, budgetBytes, warningPending]))) {
      notifyListeners();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    final pending = flush();
    _closed = true;
    await pending.catchError((Object _) {});
    await _queue;
    try {
      await _store.close();
    } catch (_) {}
    dispose();
  }
}
