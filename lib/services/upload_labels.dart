import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local retry queue. No message, room, filename or encryption key.
class UploadLabels {
  UploadLabels(this.account, this.post, {FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  final String account;
  final Future<void> Function(List<Map<String, Object?>>) post;
  final FlutterSecureStorage storage;
  final _pending = <String, Map<String, Object?>>{};
  Future<void> _writes = Future.value();
  Future<void>? _flushing;
  DateTime? _retryAfter;
  String? warning;
  String get _key =>
      'send.upload-labels.${sha256.convert(utf8.encode(account))}';
  Future<void> open() async {
    final raw = await storage.read(key: _key);
    if (raw == null) return;
    final rows = jsonDecode(raw);
    if (rows is! List || rows.length > 4096) {
      throw const FormatException('Invalid label queue');
    }
    for (final row in rows) {
      if (row is! Map ||
          row['media_id'] is! String ||
          !RegExp(
            r'^[A-Za-z0-9_-]{1,255}$',
          ).hasMatch(row['media_id'] as String) ||
          !{
            'images',
            'videos',
            'gifs',
            'audio',
            'other',
          }.contains(row['kind']) ||
          !{'upload', 'klipy', 'asset'}.contains(row['source'])) {
        continue;
      }
      _pending[row['media_id'] as String] = Map<String, Object?>.from(row);
    }
  }

  Future<void> _save() {
    final encoded = jsonEncode(_pending.values.toList());
    return _writes = _writes
        .catchError((Object _) {})
        .then((_) => storage.write(key: _key, value: encoded));
  }

  Future<void> add(String id, String kind, String source) async {
    final old = _pending[id];
    if (old?['source'] == 'asset' ||
        (old?['kind'] == kind && old?['source'] == source)) {
      return;
    }
    if (_pending.length >= 4096 && old == null) {
      throw StateError('Storage label queue is full.');
    }
    _pending[id] = {'media_id': id, 'kind': kind, 'source': source};
    await _save();
  }

  Future<void> flush({bool force = false}) {
    if (force) _retryAfter = null;
    if (_retryAfter?.isAfter(DateTime.now()) == true) return Future.value();
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  Future<void> _flush() async {
    try {
      while (_pending.isNotEmpty) {
        final rows = _pending.values.take(100).toList();
        await post(rows);
        for (final row in rows) {
          if (identical(_pending[row['media_id']], row)) {
            _pending.remove(row['media_id']);
          }
        }
        await _save();
      }
      warning = null;
    } catch (_) {
      _retryAfter = DateTime.now().add(const Duration(minutes: 2));
      warning =
          'Upload categories are waiting to sync. Server usage still includes these files.';
    }
  }
}
