import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small private browser documents, separate from SDK-owned Matrix IndexedDB.
/// Uses the existing secure-storage plugin's WebCrypto implementation, never
/// custom encryption. Clearing site data removes these records and the session;
/// origin security is still essential because no browser store defeats XSS.
abstract final class BrowserPrivateStore {
  static const _storage = FlutterSecureStorage();
  static Future<String?> read(String name) =>
      _storage.read(key: 'deltiecord.$name');
  static Future<void> write(String name, String? value) => value == null
      ? _storage.delete(key: 'deltiecord.$name')
      : _storage.write(key: 'deltiecord.$name', value: value);
}
