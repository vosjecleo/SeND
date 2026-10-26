import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const personalDataPrefix = 'net.deltiecord.personal.v1.';

/// Each installation owns a snapshot. Per-item logical clocks merge edits;
/// cumulative per-installation counters cannot double-count sync replays.
class PersonalData extends ChangeNotifier {
  PersonalData({
    required this.account,
    required this.write,
    FlutterSecureStorage? storage,
  }) : storage = storage ?? const FlutterSecureStorage();
  final String account;
  final Future<void> Function(String, Map<String, Object?>) write;
  final FlutterSecureStorage storage;
  final _records = <String, Map<String, dynamic>>{};
  Map<String, dynamic> _own = {};
  String _installation = '';
  int _clock = 0;
  bool _dirty = false, _writing = false, _closed = false;
  Timer? _saveTimer;
  String? warning;
  Map<String, Object?>? _resolved;
  String? _remoteFingerprint;
  DateTime? _retryAfter;
  Future<void> _storageQueue = Future.value();
  String get _key => 'send.personal.${sha256.convert(utf8.encode(account))}';
  String get eventType => '$personalDataPrefix$_installation';
  bool get ready => _installation.isNotEmpty;

  Future<void> open(Map<String, Object?> records) async {
    final raw = await storage.read(key: _key);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map;
        _installation = data['installation'] as String? ?? '';
        _own = Map<String, dynamic>.from(data['record'] as Map? ?? {});
        _dirty = data['dirty'] == true;
      } catch (_) {
        _own = {};
      }
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(_installation)) {
      _installation = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    }
    merge(records);
    await _persist();
    if (_dirty) unawaited(flush());
  }

  Map<String, dynamic> _valid(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        jsonEncode(value).length > 240 * 1024) {
      return {};
    }
    final entries = value['values'], usage = value['usage'];
    return {
      'version': 1,
      'values': entries is Map
          ? Map.fromEntries(
              entries.entries
                  .take(1000)
                  .where(
                    (e) =>
                        e.key is String &&
                        (e.key as String).length <= 2048 &&
                        e.value is Map &&
                        e.value['clock'] is int &&
                        e.value['clock'] >= 0 &&
                        e.value['clock'] < 1 << 52,
                  )
                  .map(
                    (e) => MapEntry(
                      e.key as String,
                      Map<String, dynamic>.from(e.value as Map),
                    ),
                  ),
            )
          : <String, dynamic>{},
      'usage': usage is Map
          ? Map.fromEntries(
              usage.entries
                  .take(600)
                  .where(
                    (e) =>
                        e.key is String &&
                        (e.key as String).length <= 2048 &&
                        e.value is int &&
                        e.value >= 0 &&
                        e.value < 1 << 52,
                  )
                  .map((e) => MapEntry(e.key as String, e.value)),
            )
          : <String, dynamic>{},
    };
  }

  void merge(Map<String, Object?> records) {
    if (_closed) return;
    final remote = {
      for (final e
          in records.entries
              .where((e) => e.key.startsWith(personalDataPrefix))
              .take(64))
        e.key: _valid(e.value),
    };
    final fingerprint = jsonEncode(remote);
    if (_remoteFingerprint == fingerprint) {
      if (_dirty) unawaited(flush());
      return;
    }
    _remoteFingerprint = fingerprint;
    _resolved = null;
    _records.clear();
    _records.addAll(remote);
    _own = _valid(_own);
    if (_own.isEmpty) {
      _own = {
        'version': 1,
        'values': <String, dynamic>{},
        'usage': <String, dynamic>{},
      };
    }
    final received = _records[eventType];
    if (received != null) {
      final local = _own['values'] as Map;
      for (final e in (received['values'] as Map? ?? {}).entries) {
        if (local[e.key] == null || e.value['clock'] > local[e.key]['clock']) {
          local[e.key] = e.value;
        }
      }
      final usage = _own['usage'] as Map;
      for (final e in (received['usage'] as Map? ?? {}).entries) {
        usage[e.key] = max(usage[e.key] as int? ?? 0, e.value as int);
      }
    }
    _records[eventType] = _own;
    for (final record in _records.values) {
      for (final value in (record['values'] as Map? ?? {}).values) {
        if (value is Map && value['clock'] is int) {
          _clock = max(_clock, value['clock'] as int);
        }
      }
    }
    notifyListeners();
    if (_dirty && !_writing) unawaited(flush());
  }

  Map<String, Object?> get values {
    if (_resolved case final cached?) return cached;
    final winning = <String, ({int clock, String device, Object? value})>{};
    for (final record in _records.entries) {
      for (final entry in (record.value['values'] as Map? ?? {}).entries) {
        final value = entry.value as Map;
        final old = winning[entry.key];
        final clock = value['clock'] as int;
        if (old == null ||
            clock > old.clock ||
            (clock == old.clock && record.key.compareTo(old.device) > 0)) {
          winning[entry.key as String] = (
            clock: clock,
            device: record.key,
            value: value['value'],
          );
        }
      }
    }
    return _resolved = Map.unmodifiable(
      winning.map((key, value) => MapEntry(key, value.value)),
    );
  }

  Object? get(String key) => values[key];
  Map<String, int> usage(String kind) {
    final result = <String, int>{};
    for (final record in _records.values) {
      for (final entry in (record['usage'] as Map? ?? {}).entries) {
        final key = entry.key as String;
        if (key.startsWith('$kind:')) {
          final id = key.substring(kind.length + 1);
          result[id] = (result[id] ?? 0) + (entry.value as int);
        }
      }
    }
    return result;
  }

  List<String> favourites(String kind) => values.entries
      .where(
        (e) =>
            e.key.startsWith('fav.$kind:') &&
            e.value != null &&
            e.value != false,
      )
      .map((e) => e.key.substring(kind.length + 5))
      .take(100)
      .toList();
  bool archived(String room) => get('archive:$room') == true;
  bool pinned(String room) => get('pin:$room') == true;
  Map<String, String> get folders => {
    for (final e in values.entries)
      if (e.key.startsWith('folder:') && e.value is String)
        e.key.substring(7): e.value as String,
  };
  String? folderFor(String space) {
    final id = get('folderOf:$space');
    return id is String && folders.containsKey(id) ? id : null;
  }

  List<String> get spaceOrder =>
      (get('spaceOrder') as List? ?? []).whereType<String>().toList();

  Future<void> set(String key, Object? value) async {
    if (!ready || _closed || key.length > 2048) return;
    if (jsonEncode(value).length > 16000) {
      throw StateError('Setting is too large');
    }
    final values = _own['values'] as Map<String, dynamic>;
    if (key.startsWith('gif:') && !values.containsKey(key)) {
      final old = values.keys.where((key) => key.startsWith('gif:')).toList()
        ..sort(
          (a, b) =>
              (values[a]['clock'] as int).compareTo(values[b]['clock'] as int),
        );
      for (final expired in old.take(max(0, old.length - 199))) {
        values.remove(expired);
      }
    }
    if (!values.containsKey(key) && values.length >= 1000) {
      throw StateError('Personal settings limit reached.');
    }
    final existed = values.containsKey(key), old = values[key];
    values[key] = {'clock': ++_clock, 'value': value};
    if (utf8.encode(jsonEncode(_own)).length > 240 * 1024) {
      if (existed) {
        values[key] = old;
      } else {
        values.remove(key);
      }
      throw StateError('Personal settings storage limit reached.');
    }
    await _changed();
  }

  Future<void> recordUsage(String kind, String key) async {
    if (!ready || _closed || key.length > 2048) return;
    final usage = _own['usage'] as Map<String, dynamic>;
    final id = '$kind:$key';
    usage[id] = (usage[id] as int? ?? 0) + 1;
    final keys = usage.keys.where((k) => k.startsWith('$kind:')).toList();
    keys.sort((a, b) => (usage[a] as int).compareTo(usage[b] as int));
    for (final key in keys.take(max(0, keys.length - 200))) {
      usage.remove(key);
    }
    while (utf8.encode(jsonEncode(usage)).length > 32 * 1024 &&
        usage.isNotEmpty) {
      final oldest = usage.keys.reduce(
        (a, b) => (usage[a] as int) <= (usage[b] as int) ? a : b,
      );
      usage.remove(oldest);
    }
    await _changed();
  }

  Future<void> setAll(Map<String, Object?> changes) async {
    if (!ready || _closed) return;
    final previous = _own['values'];
    final next = Map<String, dynamic>.from(previous as Map);
    for (final entry in changes.entries) {
      if (entry.key.length > 2048 || jsonEncode(entry.value).length > 16000) {
        throw StateError('Setting is too large');
      }
      next[entry.key] = {'clock': ++_clock, 'value': entry.value};
    }
    if (next.length > 1000) {
      throw StateError('Personal settings limit reached.');
    }
    _own['values'] = next;
    if (utf8.encode(jsonEncode(_own)).length > 240 * 1024) {
      _own['values'] = previous;
      throw StateError('Personal settings storage limit reached.');
    }
    await _changed();
  }

  Future<void> _changed() async {
    _resolved = null;
    _dirty = true;
    _records[eventType] = _own;
    notifyListeners();
    await _persist();
    if (_closed) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 750),
      () => unawaited(flush()),
    );
  }

  Future<void> _persist() {
    final snapshot = jsonEncode({
      'installation': _installation,
      'record': _own,
      'dirty': _dirty,
    });
    final pending = _storageQueue
        .catchError((Object _) {})
        .then((_) => storage.write(key: _key, value: snapshot));
    _storageQueue = pending;
    return pending;
  }

  Future<void> flush() async {
    if (_writing ||
        !_dirty ||
        _closed ||
        (_retryAfter != null && DateTime.now().isBefore(_retryAfter!))) {
      return;
    }
    _writing = true;
    final snapshot = jsonEncode(_own);
    try {
      if (utf8.encode(snapshot).length > 240 * 1024) {
        throw StateError('Personal data limit reached');
      }
      await write(
        eventType,
        Map<String, Object?>.from(jsonDecode(snapshot) as Map),
      );
      if (snapshot == jsonEncode(_own)) _dirty = false;
      warning = null;
      _retryAfter = null;
      await _persist();
    } catch (_) {
      warning =
          'Saved on this device. Personal settings will sync when connected.';
      _retryAfter = DateTime.now().add(const Duration(seconds: 30));
      _saveTimer?.cancel();
      if (!_closed) {
        _saveTimer = Timer(
          const Duration(seconds: 31),
          () => unawaited(flush()),
        );
      }
    } finally {
      _writing = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _saveTimer?.cancel();
    _closed = true;
    // Changes are already saved locally. Do not start another account-data
    // request while logging out; the next login resumes any pending write.
    dispose();
  }
}
