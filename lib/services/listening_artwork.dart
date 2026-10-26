import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'platform_io.dart';
import '../models/user_activity.dart';

/// Optional public metadata lookup. Fixed service URLs, no credentials and
/// cached misses. Never forwards the listener's username or Matrix identity.
class ListeningArtwork {
  ListeningArtwork({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  final _cache = <String, Uri?>{};
  DateTime _after = DateTime(1970);
  Future<Uri?> lookup(String artist, String album) async {
    if (artist.trim().isEmpty || album.trim().isEmpty) return null;
    final key = '${artist.toLowerCase()}\n${album.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key];
    if (DateTime.now().isBefore(_after)) return null;
    _after = DateTime.now().add(const Duration(seconds: 2));
    Uri? art;
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 5);
    Future<Map?> json(Uri uri) async {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      if (!kIsWeb) {
        request.headers.set('User-Agent', 'SeND/0.9 (https://deltie.net/SeND)');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 5))) {
        if (bytes.length + part.length > 256 * 1024) return null;
        bytes.addAll(part);
      }
      final result = jsonDecode(utf8.decode(bytes));
      return result is Map ? result : null;
    }

    String quoted(String value) =>
        value.replaceAll(RegExp(r'["\\]'), ' ').trim();
    try {
      final data = await json(
        Uri.https('musicbrainz.org', '/ws/2/release/', {
          'query': 'release:"${quoted(album)}" AND artist:"${quoted(artist)}"',
          'fmt': 'json',
          'limit': '3',
        }),
      );
      final releases = data?['releases'];
      if (releases is List) {
        for (final release in releases.whereType<Map>()) {
          if ('${release['title']}'.toLowerCase() !=
              album.trim().toLowerCase()) {
            continue;
          }
          final credits = release['artist-credit'];
          if (credits is! List ||
              !credits.whereType<Map>().any(
                (c) =>
                    '${c['name']}'.toLowerCase() == artist.trim().toLowerCase(),
              )) {
            continue;
          }
          final id = '${release['id']}';
          if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) continue;
          final cover = await json(
            Uri.https('coverartarchive.org', '/release/$id'),
          );
          final images = cover?['images'];
          if (images is! List) continue;
          for (final image in images.whereType<Map>()) {
            if (image['front'] != true || image['thumbnails'] is! Map) continue;
            final raw = Uri.tryParse(
              '${image['thumbnails']['500'] ?? image['thumbnails']['250']}',
            );
            // CAA's older responses use HTTP links for the same HTTPS assets.
            art = validListeningArtwork(
              raw?.replace(scheme: 'https').toString(),
            );
            if (art != null) break;
          }
          if (art != null) break;
        }
      }
      _cache[key] = art;
      while (_cache.length > 100) {
        _cache.remove(_cache.keys.first);
      }
    } catch (_) {
      _after = DateTime.now().add(const Duration(minutes: 1));
    } finally {
      client.close(force: true);
    }
    return art;
  }
}
