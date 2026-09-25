import 'dart:convert';
import '../models/user_activity.dart';
import 'activity_candidate.dart';
import 'platform_io.dart';

/// Foreground-only public now-playing reader shared by native and web clients.
/// The controller owns lifecycle/consent; this class owns rate/cache bounds.
class LastFmActivitySource {
  LastFmActivitySource({
    HttpClient Function()? clientFactory,
    DateTime Function()? now,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _now = now ?? DateTime.now;
  final HttpClient Function() _clientFactory;
  final DateTime Function() _now;
  DateTime? _after;
  String? _identity;
  ActivityCandidate? _cached;
  LastFmTrack? recent;

  void clear() {
    _cached = null;
    recent = null;
    // Preserve the rate-limit deadline across background/resume cycles.
  }

  /// Keep a still-fresh response for quick resume. The controller suppresses
  /// publication in the background; retaining local cache does not share it.
  /// Clearing it while retaining _after creates a minute-long empty result.
  void suspend() {
    if (_after == null || !_now().isBefore(_after!)) clear();
  }

  Future<ActivityCandidate?> scan(ActivitySettings settings) async {
    if (settings.lastFmUser.isEmpty || settings.lastFmKey.isEmpty) {
      _cached = null;
      recent = null;
      return null;
    }
    final identity = '${settings.lastFmUser}:${settings.lastFmKey}';
    if (_identity != identity) {
      _cached = null;
      recent = null;
      _after = null;
      _identity = identity;
    }
    if (_after != null && _now().isBefore(_after!)) return _cached;
    _after = _now().add(const Duration(minutes: 1));
    _cached = null;
    recent = null;
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.https('ws.audioscrobbler.com', '/2.0/', {
          'method': 'user.getrecenttracks',
          'user': settings.lastFmUser,
          'api_key': settings.lastFmKey,
          'format': 'json',
          'limit': '2',
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode == 429) {
        _after = _now().add(
          Duration(
            seconds:
                (int.tryParse(response.headers.value('retry-after') ?? '') ??
                        300)
                    .clamp(60, 3600),
          ),
        );
        return null;
      }
      if (response.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        if (bytes.length + chunk.length > 128 * 1024) return null;
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map) return null;
      if (data['error'] == 29) {
        _after = _now().add(const Duration(minutes: 5));
        return null;
      }
      final cache = response.headers.value('cache-control') ?? '';
      final seconds =
          int.tryParse(
            RegExp(r'max-age=(\d+)').firstMatch(cache)?.group(1) ?? '',
          ) ??
          60;
      _after = _now().add(
        Duration(
          seconds: cache.contains('no-store') || cache.contains('no-cache')
              ? 0
              : seconds.clamp(0, 3600),
        ),
      );
      final activity = lastFmNowPlaying(data, settings.lastFmUser);
      recent = lastFmRecentlyPlayed(data, settings.lastFmUser);
      if (!cache.contains('no-store') && !cache.contains('no-cache')) {
        _cached = activity;
      }
      return activity;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

LastFmTrack? lastFmRecentlyPlayed(Map data, String user) {
  final recent = data['recenttracks'];
  final tracks = recent is Map ? recent['track'] : null;
  if (tracks is! List) return null;
  String bounded(Object? value, int limit) => value is String
      ? value.trim().substring(0, value.trim().length.clamp(0, limit))
      : '';
  for (final track in tracks.take(2)) {
    if (track is! Map) continue;
    final attr = track['@attr'];
    if (attr is Map && attr['nowplaying'] == 'true') continue;
    final date = track['date'],
        artist = track['artist'],
        album = track['album'];
    final seconds = date is Map ? int.tryParse('${date['uts']}') : null;
    if (seconds == null) continue;
    final value = LastFmTrack.fromJson({
      'name': bounded(track['name'], 128),
      'artist': bounded(artist is Map ? artist['#text'] : artist, 256),
      'album': bounded(album is Map ? album['#text'] : album, 256),
      'url':
          (validLastFmUrl(track['url']) ??
                  Uri.https('www.last.fm', '/user/$user'))
              .toString(),
      'played_at': seconds * 1000,
    });
    if (value != null) return value;
  }
  return null;
}

ActivityCandidate? lastFmNowPlaying(Map data, String user) {
  final recent = data['recenttracks'];
  final tracks = recent is Map ? recent['track'] : null;
  if (tracks is! List || tracks.isEmpty || tracks.first is! Map) return null;
  final track = tracks.first as Map;
  final attributes = track['@attr'];
  if (attributes is! Map ||
      attributes['nowplaying'] != 'true' ||
      track['name'] is! String) {
    return null;
  }
  String bounded(Object? text, int length) {
    final value = text is String ? text.trim() : '';
    return value.substring(0, value.length.clamp(0, length));
  }

  final artist = track['artist'];
  Uri? artwork;
  var artworkRank = -1;
  final images = track['image'];
  if (images is List) {
    for (final image in images.take(12)) {
      if (image is! Map) continue;
      final url = validLastFmArtwork(image['#text']);
      final rank = const [
        'small',
        'medium',
        'large',
        'extralarge',
        'mega',
      ].indexOf('${image['size']}');
      if (url != null && rank > artworkRank) {
        artwork = url;
        artworkRank = rank;
      }
    }
  }
  return ActivityCandidate(
    id: 'lastfm',
    name: bounded(track['name'], 128),
    kind: ActivityKind.music,
    details: bounded(artist is Map ? artist['#text'] : null, 256),
    // Written artwork-display permission confirmed by the owner. Reference the
    // supplied CDN URL; do not mirror artwork or invent a larger rendition.
    lastFmArtwork: artwork,
    lastFmUrl:
        validLastFmUrl(track['url']) ?? Uri.https('www.last.fm', '/user/$user'),
  );
}
