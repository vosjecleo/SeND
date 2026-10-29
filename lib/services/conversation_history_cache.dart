import 'dart:async';
import 'dart:convert';

/// Small encrypted-database-backed snapshots for reopening conversations. Not
/// an archive: server pagination always starts fresh, so cached rows never cause
/// a history gap. Owns its loading, bounded eviction and debounced write life.
final class ConversationHistoryCache {
  ConversationHistoryCache({
    required this.owner,
    required this.read,
    required this.write,
  });
  final Object owner;
  final Future<Map<String, Object?>?> Function() read;
  final Future<void> Function(Map<String, Object?>) write;
  static const maximumConversations = 16,
      maximumEvents = 90,
      maximumBytes = 2 * 1024 * 1024;
  final _entries = <String, List<Map<String, Object?>>>{};
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  Timer? _timer;
  bool _disposed = false;

  Future<void> _load() => _loading ??= () async {
    try {
      final saved = await read();
      if (_disposed) return;
      final entries = saved?['entries'];
      if (saved?['version'] != 1 || entries is! Map) return;
      for (final entry in entries.entries) {
        if (entry.key is! String || entry.value is! List) continue;
        final rows = (entry.value as List)
            .whereType<Map>()
            .map((m) => Map<String, Object?>.from(m))
            .toList();
        if (rows.length <= maximumEvents) _entries[entry.key as String] = rows;
      }
      _prune();
    } catch (_) {
      /* Optional cache failure must not block a conversation. */
    }
  }();

  Future<List<Map<String, Object?>>> get(String key) async {
    await _load();
    if (_disposed) return const [];
    final rows = _entries.remove(key);
    if (rows == null) return const [];
    _entries[key] = rows;
    return [for (final row in rows) Map<String, Object?>.from(row)];
  }

  Future<void> put(String key, List<Map<String, Object?>> rows) async {
    await _load();
    if (_disposed) return;
    final bounded = rows.take(maximumEvents).toList();
    if (jsonEncode(bounded) == jsonEncode(_entries[key])) return;
    _entries.remove(key);
    _entries[key] = bounded;
    _prune();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () => unawaited(flush()));
  }

  void _prune() {
    while (_entries.isNotEmpty &&
        (_entries.length > maximumConversations ||
            utf8.encode(jsonEncode(_entries)).length > maximumBytes)) {
      _entries.remove(_entries.keys.first);
    }
  }

  Future<void> flush() {
    _timer?.cancel();
    if (_disposed) return Future<void>.value();
    final snapshot =
        jsonDecode(jsonEncode({'version': 1, 'entries': _entries}))
            as Map<String, Object?>;
    final next = _writes.then((_) async {
      if (!_disposed) {
        try {
          await write(snapshot);
        } catch (_) {
          /* Server history remains authoritative. */
        }
      }
    });
    _writes = next;
    return next;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _entries.clear();
  }
}
