import 'dart:convert';
import 'gif_categories.dart';

/// Device-local category thumbnail references only, never GIF bytes, messages,
/// arbitrary user searches or an offline catalogue of full result pages.
class GifCategoryCache {
  GifCategoryCache({
    required this.read,
    required this.write,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  final DateTime Function() clock;
  static const lifetime = Duration(hours: 12);
  static const maximumCharacters = 128 * 1024;
  final _entries = <String, (DateTime, List<Map<String, Object?>>)>{};
  final _pending = <String, Future<List<Map<String, Object?>>>>{};
  Future<void>? _opening;
  Future<void> _writes = Future.value();

  bool _fresh(DateTime fetched) {
    final age = clock().difference(fetched);
    return !age.isNegative && age < lifetime;
  }

  List<Map<String, Object?>> _links(Iterable values) {
    final links = <Map<String, Object?>>[];
    for (final value in values.take(5)) {
      if (value is! Map) continue;
      bool valid(Object? raw) {
        if (raw is! String || raw.length > 2048) return false;
        final uri = Uri.tryParse(raw);
        return uri != null &&
            uri.scheme == 'https' &&
            uri.host == 'static.klipy.com' &&
            uri.userInfo.isEmpty &&
            (!uri.hasPort || uri.port == 443);
      }

      if (!valid(value['preview_url']) || !valid(value['share_url'])) continue;
      links.add({
        'preview_url': value['preview_url'],
        'share_url': value['share_url'],
        'title': value['title'] is String
            ? (value['title'] as String).substring(
                0,
                (value['title'] as String).length.clamp(0, 160),
              )
            : 'GIF',
        for (final dimension in ['width', 'height'])
          if (value[dimension] is int &&
              (value[dimension] as int) > 0 &&
              (value[dimension] as int) <= 32768)
            dimension: value[dimension],
        if (value['provider_id'] is String &&
            (value['provider_id'] as String).length <= 240)
          'provider_id': value['provider_id'],
      });
    }
    return links;
  }

  Future<void> _open() async {
    try {
      final raw = await read();
      if (raw == null || raw.length > maximumCharacters) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['entries'] is! Map) {
        return;
      }
      final entries = decoded['entries'] as Map;
      for (final query in gifCategorySearches) {
        final value = entries[query];
        if (value is! Map || value['at'] is! int || value['links'] is! List) {
          continue;
        }
        final at = DateTime.fromMillisecondsSinceEpoch(value['at'] as int);
        if (_fresh(at)) _entries[query] = (at, _links(value['links'] as List));
      }
    } catch (_) {
      /* A corrupt or unavailable cache must not block the picker. */
    }
  }

  Future<List<Map<String, Object?>>> get(
    String query,
    Future<List<Map<String, Object?>>> Function() loader,
  ) async {
    if (!gifCategorySearches.contains(query)) {
      throw ArgumentError('Not a built-in GIF category');
    }
    await (_opening ??= _open());
    final cached = _entries[query];
    if (cached != null && _fresh(cached.$1)) return cached.$2;
    final pending = _pending[query];
    if (pending != null) return pending;
    final work = _fetch(query, loader);
    _pending[query] = work;
    try {
      return await work;
    } finally {
      if (identical(_pending[query], work)) _pending.remove(query);
    }
  }

  Future<List<Map<String, Object?>>> _fetch(
    String query,
    Future<List<Map<String, Object?>>> Function() loader,
  ) async {
    final result = _links(await loader());
    _entries.removeWhere((_, entry) => !_fresh(entry.$1));
    _entries[query] = (clock(), result);
    final encoded = jsonEncode({
      'version': 1,
      'entries': {
        for (final entry in _entries.entries)
          entry.key: {
            'at': entry.value.$1.millisecondsSinceEpoch,
            'links': entry.value.$2,
          },
      },
    });
    if (encoded.length <= maximumCharacters) {
      final next = _writes
          .catchError((Object _) {})
          .then((_) => write(encoded));
      _writes = next;
      try {
        await next;
      } catch (_) {
        /* Keep this session's bounded result. */
      }
    }
    return result;
  }
}
