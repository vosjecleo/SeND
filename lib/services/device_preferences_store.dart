import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'preference_scopes.dart';

/// Per-installation, per-account preferences. The key contains no account ID.
final class DevicePreferencesStore {
  DevicePreferencesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  Future<void> _writes = Future<void>.value();
  String _key(String user) =>
      'send.device_preferences.v1.${sha256.convert(utf8.encode(user))}';

  Future<Map<String, Object?>?> load(String user) async {
    await _writes;
    final raw = await _storage.read(key: _key(user));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != 1 ||
        decoded['values'] is! Map) {
      throw const FormatException('Device settings could not be read.');
    }
    final values = decoded['values'] as Map;
    if (!PreferenceScopes.deviceKeys.every(values.containsKey)) {
      throw const FormatException('Device settings are incomplete.');
    }
    return {for (final key in PreferenceScopes.deviceKeys) key: values[key]};
  }

  Future<void> save(String user, Map<String, Object?> values) {
    final encoded = jsonEncode({'schema': 1, 'values': values});
    final next = _writes.then(
      (_) => _storage.write(key: _key(user), value: encoded),
    );
    _writes = next.catchError((Object _) {});
    return next;
  }
}
