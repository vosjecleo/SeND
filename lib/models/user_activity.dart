import 'dart:convert';
import 'package:crypto/crypto.dart';

enum ActivityKind { game, music, application }

const activityProfileField = 'net.deltiecord.activity';
const activityDevicePrefix = 'net.deltiecord.activity.device.';
String activityDeviceField(String deviceId) =>
    '$activityDevicePrefix${sha256.convert(utf8.encode(deviceId))}';

/// Independently selected slots from unexpired device-owned profile fields.
/// Native music wins over Last.fm now-playing; completed scrobbles never become
/// a live activity. Selection is deterministic on every receiving client.
class UserActivities {
  const UserActivities({this.program, this.music, this.recent});
  final UserActivity? program, music;
  final LastFmTrack? recent;
  UserActivity? get primary => program ?? music;
  List<UserActivity> get live => [?program, ?music];

  static UserActivities fromRecords(Map<String, Object?> records) {
    final entries = records.entries
        .where((e) => activityRecordExpiry(e.value) != null)
        .toList();
    entries.sort((a, b) {
      final order = activityRecordExpiry(
        b.value,
      )!.compareTo(activityRecordExpiry(a.value)!);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
    UserActivity? program, music;
    LastFmTrack? recent;
    for (final entry in entries.take(64)) {
      final record = entry.value as Map;
      final slots = record['slots'];
      final legacy = UserActivity.fromJson(record);
      final p = slots is Map
          ? UserActivity.fromJson(slots['program'])
          : legacy?.kind != ActivityKind.music
          ? legacy
          : null;
      final m = slots is Map
          ? UserActivity.fromJson(slots['music'])
          : legacy?.kind == ActivityKind.music
          ? legacy
          : null;
      if (p != null && p.kind != ActivityKind.music) program ??= p;
      if (m != null &&
          m.kind == ActivityKind.music &&
          (music == null || (music.lastFmUrl != null && m.lastFmUrl == null))) {
        music = m;
      }
      final track = LastFmTrack.fromJson(record['lastfm_recent']);
      if (track != null &&
          (recent == null || track.playedAt.isAfter(recent.playedAt))) {
        recent = track;
      }
    }
    return UserActivities(program: program, music: music, recent: recent);
  }
}

const lastFmPublicDisplayApproved = bool.fromEnvironment(
  'LASTFM_PUBLIC_DISPLAY_APPROVED',
  defaultValue: true, // Written approval confirmed by the app owner.
);

/// A completed scrobble, not a live activity. Stored as an optional field in the
/// same expiring activity record; legacy clients simply ignore this field.
class LastFmTrack {
  const LastFmTrack({
    required this.name,
    required this.artist,
    required this.album,
    required this.url,
    required this.playedAt,
  });
  final String name, artist, album;
  final Uri url;
  final DateTime playedAt;
  Map<String, Object> toJson() => {
    'name': name,
    'artist': artist,
    'album': album,
    'url': url.toString(),
    'played_at': playedAt.millisecondsSinceEpoch,
  };
  static LastFmTrack? fromJson(Object? value, {DateTime? now}) {
    if (value is! Map) return null;
    final name = value['name'],
        artist = value['artist'],
        album = value['album'];
    final played = value['played_at'], url = validLastFmUrl(value['url']);
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 128 ||
        artist is! String ||
        artist.length > 256 ||
        album is! String ||
        album.length > 256 ||
        played is! int ||
        played <= 0 ||
        played >
            (now ?? DateTime.now())
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch ||
        url == null) {
      return null;
    }
    return LastFmTrack(
      name: name,
      artist: artist,
      album: album,
      url: url,
      playedAt: DateTime.fromMillisecondsSinceEpoch(played),
    );
  }
}

DateTime? activityRecordExpiry(Object? value, {DateTime? now}) {
  if (value is! Map || value['version'] != 1 || value['expires_at'] is! int) {
    return null;
  }
  final expiry = value['expires_at'] as int;
  final current = now ?? DateTime.now();
  if (expiry <= current.millisecondsSinceEpoch ||
      expiry >
          current.add(const Duration(minutes: 10)).millisecondsSinceEpoch) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(expiry);
}

/// Position sampled from a player; clients interpolate without network ticks.
class ActivityPlayback {
  const ActivityPlayback({
    required this.positionMs,
    required this.durationMs,
    required this.sampledAt,
    this.playing = true,
  });
  final int positionMs, durationMs;
  final DateTime sampledAt;
  final bool playing;
  int positionAt(DateTime now) =>
      (positionMs +
              (playing
                  ? now.difference(sampledAt).inMilliseconds.clamp(0, 86400000)
                  : 0))
          .clamp(0, durationMs);
  Map<String, Object> toJson() => {
    'position_ms': positionMs,
    'duration_ms': durationMs,
    'sampled_at': sampledAt.millisecondsSinceEpoch,
    'playing': playing,
  };
  static ActivityPlayback? fromJson(Object? value, {DateTime? now}) {
    if (value is! Map) return null;
    final p = value['position_ms'],
        d = value['duration_ms'],
        s = value['sampled_at'];
    final current = now ?? DateTime.now();
    if (p is! int ||
        d is! int ||
        s is! int ||
        p < 0 ||
        d <= 0 ||
        d > 86400000 ||
        p > d ||
        s <
            current
                .subtract(const Duration(minutes: 10))
                .millisecondsSinceEpoch ||
        s > current.add(const Duration(seconds: 30)).millisecondsSinceEpoch ||
        value['playing'] is! bool) {
      return null;
    }
    return ActivityPlayback(
      positionMs: p,
      durationMs: d,
      sampledAt: DateTime.fromMillisecondsSinceEpoch(s),
      playing: value['playing'],
    );
  }
}

Uri? validLastFmUrl(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host == 'www.last.fm' &&
          uri.userInfo.isEmpty &&
          !uri.hasPort &&
          (uri.path.startsWith('/music/') || uri.path.startsWith('/user/'))
      ? uri
      : null;
}

/// Only API-provided HTTPS Last.fm CDN artwork, never arbitrary profile URLs.
Uri? validLastFmArtwork(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.userInfo.isEmpty &&
          !uri.hasPort &&
          !uri.hasQuery &&
          !uri.hasFragment &&
          uri.path.startsWith('/i/u/') &&
          (uri.host == 'lastfm.freetls.fastly.net' ||
              uri.host == 'lastfm-img2.akamaized.net')
      ? uri
      : null;
}

/// Public, short-lived presentation metadata. Never contains process paths.
class UserActivity {
  const UserActivity({
    required this.kind,
    required this.name,
    required this.expiresAt,
    this.details = '',
    this.icon,
    this.startedAt,
    this.playback,
    this.lastFmUrl,
    this.lastFmArtwork,
  });
  final ActivityKind kind;
  final String name;
  final String details;
  final Uri? icon;
  final DateTime? startedAt;
  final ActivityPlayback? playback;
  final Uri? lastFmUrl;
  final Uri? lastFmArtwork;
  final DateTime expiresAt;
  bool get expired => !expiresAt.isAfter(DateTime.now());
  String get label =>
      '${switch (kind) {
        ActivityKind.game => 'Playing',
        ActivityKind.music => 'Listening to',
        ActivityKind.application => 'Using',
      }} $name';
  Map<String, Object?> toJson() => {
    'version': 1,
    'kind': kind.name,
    'name': name,
    'details': details,
    if (icon != null) 'icon': icon.toString(),
    if (startedAt != null) 'started_at': startedAt!.millisecondsSinceEpoch,
    if (playback != null) 'playback': playback!.toJson(),
    if (lastFmUrl != null) 'lastfm_url': lastFmUrl.toString(),
    if (lastFmUrl != null && lastFmArtwork != null)
      'lastfm_artwork': lastFmArtwork.toString(),
    'expires_at': expiresAt.millisecondsSinceEpoch,
  };
  static UserActivity? fromJson(Object? value, {DateTime? now}) {
    if (value is! Map || value['version'] != 1) return null;
    final name = value['name'];
    final expiry = value['expires_at'];
    final kind = ActivityKind.values
        .where((e) => e.name == value['kind'])
        .firstOrNull;
    if (kind == null ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 128 ||
        expiry is! int) {
      return null;
    }
    final current = now ?? DateTime.now();
    if (expiry <= current.millisecondsSinceEpoch ||
        expiry >
            current.add(const Duration(minutes: 10)).millisecondsSinceEpoch) {
      return null;
    }
    final details = value['details'];
    final rawIcon = value['icon'];
    final icon = rawIcon is String && rawIcon.length <= 2048
        ? Uri.tryParse(rawIcon)
        : null;
    final start = value['started_at'];
    return UserActivity(
      kind: kind,
      name: name.trim(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiry),
      details: details is String
          ? details.substring(0, details.length.clamp(0, 256))
          : '',
      icon: icon?.scheme == 'mxc' ? icon : null,
      playback: kind == ActivityKind.music
          ? ActivityPlayback.fromJson(value['playback'], now: current)
          : null,
      lastFmUrl: validLastFmUrl(value['lastfm_url']),
      lastFmArtwork: validLastFmUrl(value['lastfm_url']) == null
          ? null
          : validLastFmArtwork(value['lastfm_artwork']),
      startedAt:
          start is int && start > 0 && start <= current.millisecondsSinceEpoch
          ? DateTime.fromMillisecondsSinceEpoch(start)
          : null,
    );
  }
}

class ActivityRule {
  const ActivityRule({
    required this.name,
    required this.kind,
    this.allowed = true,
  });
  final String name;
  final ActivityKind kind;
  final bool allowed;
  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    'allowed': allowed,
  };
}

/// Device/account-local: deliberately excluded from synced appearance/settings.
class ActivitySettings {
  const ActivitySettings({
    this.detect = false,
    this.share = false,
    this.rpc = false,
    this.rules = const {},
    this.lastFmUser = '',
    this.lastFmKey = '',
    this.showLastFmRecent = false,
  });
  final bool detect, share, rpc;
  final bool showLastFmRecent;
  final Map<String, ActivityRule> rules;
  final String lastFmUser, lastFmKey;
  ActivitySettings copyWith({
    bool? detect,
    bool? share,
    bool? rpc,
    Map<String, ActivityRule>? rules,
    String? lastFmUser,
    String? lastFmKey,
    bool? showLastFmRecent,
  }) => ActivitySettings(
    detect: detect ?? this.detect,
    share: share ?? this.share,
    rpc: rpc ?? this.rpc,
    rules: rules ?? this.rules,
    lastFmUser: lastFmUser ?? this.lastFmUser,
    lastFmKey: lastFmKey ?? this.lastFmKey,
    showLastFmRecent: showLastFmRecent ?? this.showLastFmRecent,
  );
  Map<String, Object?> toJson() => {
    'detect': detect,
    'share': share,
    'rpc': rpc,
    'rules': rules.map((key, value) => MapEntry(key, value.toJson())),
    'lastfm_user': lastFmUser,
    'lastfm_key': lastFmKey,
    'lastfm_recent': showLastFmRecent,
  };
  factory ActivitySettings.fromJson(Object? value) {
    if (value is! Map) return const ActivitySettings();
    final rules = <String, ActivityRule>{};
    if (value['rules'] case final Map entries) {
      for (final entry in entries.entries.take(500)) {
        final rule = entry.value;
        if (entry.key is! String || rule is! Map || rule['name'] is! String) {
          continue;
        }
        final kind = ActivityKind.values
            .where((e) => e.name == rule['kind'])
            .firstOrNull;
        if (kind != null) {
          rules[entry.key] = ActivityRule(
            name: rule['name'],
            kind: kind,
            allowed: rule['allowed'] == true,
          );
        }
      }
    }
    return ActivitySettings(
      detect: value['detect'] == true,
      share: value['share'] == true,
      rpc: value['rpc'] == true,
      rules: rules,
      lastFmUser: value['lastfm_user'] is String ? value['lastfm_user'] : '',
      lastFmKey: value['lastfm_key'] is String ? value['lastfm_key'] : '',
      showLastFmRecent: value['lastfm_recent'] == true,
    );
  }
}
