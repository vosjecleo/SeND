import 'dart:convert';
import '../models/user_activity.dart';
import 'activity_candidate.dart';
import 'platform_io.dart';
import 'listening_artwork.dart';

/// Foreground-only public now-playing reader shared by native and web clients.
/// The controller owns lifecycle/consent; this class owns rate/cache bounds.
/// Libre.fm uses the compatible read endpoint, without Last.fm credentials.
class LastFmActivitySource {
  LastFmActivitySource({
    HttpClient Function()? clientFactory,
    DateTime Function()? now,
    this.libreFm = false,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _now = now ?? DateTime.now;
  final HttpClient Function() _clientFactory;
  final DateTime Function() _now;
  final bool libreFm;
  DateTime? _after;
  String? _identity;
  ActivityCandidate? _cached;
  LastFmTrack? recent;
  final _artwork = ListeningArtwork();

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
    final user = libreFm ? settings.libreFmUser : settings.lastFmUser;
    if (user.isEmpty || (!libreFm && settings.lastFmKey.isEmpty)) {
      _cached = null;
      recent = null;
      return null;
    }
    final identity = '$user:${libreFm ? "librefm" : settings.lastFmKey}';
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
        Uri.https(libreFm ? 'libre.fm' : 'ws.audioscrobbler.com', '/2.0/', {
          'method': 'user.getrecenttracks',
          'user': user,
          if (!libreFm) 'api_key': settings.lastFmKey,
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
      var activity = lastFmNowPlaying(data, user, libreFm: libreFm);
      recent = lastFmRecentlyPlayed(data, user, libreFm: libreFm);
      if (settings.lookupListeningArtwork && libreFm) {
        final tracks = (data['recenttracks'] is Map)
            ? data['recenttracks']['track']
            : null;
        final first = tracks is List && tracks.isNotEmpty && tracks.first is Map
            ? tracks.first as Map
            : null;
        final album = first?['album'];
        final art = await _artwork.lookup(
          activity?.details ?? recent?.artist ?? '',
          activity != null
              ? '${album is Map ? album['#text'] ?? '' : album ?? ''}'
              : recent?.album ?? '',
        );
        if (art != null && activity != null && activity.lastFmArtwork == null) {
          activity = ActivityCandidate(
            id: activity.id,
            name: activity.name,
            kind: activity.kind,
            details: activity.details,
            lastFmArtwork: art,
            lastFmUrl: activity.lastFmUrl,
          );
        }
        final track = recent;
        if (track != null && track.artwork == null) {
          final cover = await _artwork.lookup(track.artist, track.album);
          if (cover != null) {
            recent = LastFmTrack(
              name: track.name,
              artist: track.artist,
              album: track.album,
              url: track.url,
              playedAt: track.playedAt,
              artwork: cover,
            );
          }
        }
      }
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

LastFmTrack? lastFmRecentlyPlayed(
  Map data,
  String user, {
  bool libreFm = false,
}) {
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
          ((libreFm
                      ? _libreFmUrl(track['url'])
                      : validLastFmUrl(track['url'])) ??
                  Uri.https(
                    libreFm ? 'libre.fm' : 'www.last.fm',
                    '/user/$user',
                  ))
              .toString(),
      'played_at': seconds * 1000,
      'artwork': lastFmArtworkFromImages(track['image'])?.toString(),
    });
    if (value != null) return value;
  }
  return null;
}

ActivityCandidate? lastFmNowPlaying(
  Map data,
  String user, {
  bool libreFm = false,
}) {
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
  final artwork = lastFmArtworkFromImages(track['image']);
  return ActivityCandidate(
    id: libreFm ? 'librefm' : 'lastfm',
    name: bounded(track['name'], 128),
    kind: ActivityKind.music,
    details: bounded(artist is Map ? artist['#text'] : null, 256),
    lastFmArtwork: artwork,
    lastFmUrl:
        (libreFm ? _libreFmUrl(track['url']) : validLastFmUrl(track['url'])) ??
        Uri.https(libreFm ? 'libre.fm' : 'www.last.fm', '/user/$user'),
  );
}

Uri? _libreFmUrl(Object? value) {
  final url = validListeningUrl(value);
  return url?.host == 'libre.fm' ? url : null;
}

Uri? lastFmArtworkFromImages(Object? images) {
  Uri? artwork;
  var artworkRank = -1;
  if (images is List) {
    for (final image in images.take(12)) {
      if (image is! Map) continue;
      final url = validListeningArtwork(image['#text']);
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
  return artwork;
}
