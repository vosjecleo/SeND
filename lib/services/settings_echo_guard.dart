import 'dart:convert';

/// Ignore only known stale account-data snapshots while waiting for a local
/// write's echo. An unknown snapshot is allowed: another device may legitimately
/// supersede our update before /sync delivers our exact payload.
class SettingsEchoGuard {
  final Set<String> _stale = {};
  String? _expected;
  void expect(Map<String, Object?>? previous, Map<String, Object?> next) {
    if (previous != null) _stale.add(_key(previous));
    if (_expected != null) _stale.add(_expected!);
    _expected = _key(next);
    _stale.remove(_expected);
    while (_stale.length > 16) {
      _stale.remove(_stale.first);
    }
  }

  bool accepts(Map<String, Object?>? content) {
    if (_expected == null) return true;
    final key = _key(content);
    if (_stale.contains(key)) return false;
    clear();
    return true;
  }

  void clear() {
    _stale.clear();
    _expected = null;
  }

  String _key(Object? value) => jsonEncode(_canonical(value));
  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}
