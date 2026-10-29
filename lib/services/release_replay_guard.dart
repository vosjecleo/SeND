import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A signed manifest cannot roll the updater back to metadata this installation
/// has already superseded. This is separate from installed-version comparison.
final class ReleaseReplayGuard {
  ReleaseReplayGuard({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static Future<void> _writes = Future<void>.value();
  static const _key = 'send.release_metadata.issued.v1';

  Future<void> accept(DateTime issued) {
    final next = _writes.then((_) async {
      final raw = await _storage.read(key: _key);
      final previous = raw == null ? null : DateTime.tryParse(raw);
      if ((raw != null && previous == null) ||
          (previous != null && issued.isBefore(previous))) {
        throw const FormatException('Older release metadata was rejected.');
      }
      if (previous == null || issued.isAfter(previous)) {
        await _storage.write(
          key: _key,
          value: issued.toUtc().toIso8601String(),
        );
      }
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}
