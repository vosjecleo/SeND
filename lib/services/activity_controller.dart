import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_activity.dart';
import 'activity_candidate.dart';
import 'activity_source.dart';
import 'activity_service_error.dart';
import 'lastfm_activity.dart';

/// Activity polling is independent of sync/timeline work and bounded to people
/// recently displayed. Process information and credentials never enter sync.
class ActivityController extends ChangeNotifier {
  ActivityController({
    required this.userId,
    required this.read,
    required this.write,
    this.writeProfile,
    required this.upload,
    required this.canShare,
    this.canView,
    this.isForeground,
    this.publicLastFmApproved = lastFmPublicDisplayApproved,
    LastFmActivitySource? lastFm,
    DesktopActivitySource? source,
    FlutterSecureStorage? storage,
    this.pollInterval = const Duration(seconds: 5),
    this.heartbeat = const Duration(seconds: 55),
    Duration readStartDelay = const Duration(seconds: 15),
  }) : _source = source ?? DesktopActivitySource(),
       _lastFm = lastFm ?? LastFmActivitySource(),
       _readAfter = DateTime.now().add(readStartDelay),
       _storage = storage ?? const FlutterSecureStorage();
  final String userId;
  final Future<Object?> Function(String) read;
  final Future<void> Function(UserActivity?) write;
  final Future<void> Function(Map<String, Object?>?)? writeProfile;
  final bool publicLastFmApproved;
  final Future<Uri> Function(Uint8List) upload;
  final bool Function() canShare;
  final bool Function(String)? canView;
  final bool Function()? isForeground;
  final LastFmActivitySource _lastFm;
  bool get _foreground => isForeground?.call() ?? true;
  bool _visible(String id) => canView?.call(id) ?? true;
  bool get _enabled => settings.detect || settings.lastFmUser.isNotEmpty;
  final DesktopActivitySource _source;
  final FlutterSecureStorage _storage;
  final Duration pollInterval, heartbeat;
  final _seen = <String, DateTime>{};
  final _fetched = <String, DateTime>{};
  final _cache = <String, UserActivity?>{};
  final _recentCache = <String, ({LastFmTrack track, DateTime expiresAt})>{};
  final _icons = <String, Uri>{};
  DateTime _readAfter;
  ActivitySettings settings = const ActivitySettings();
  List<ActivityCandidate> candidates = const [];
  String? warning;
  Timer? _timer;
  Timer? _initialRead;
  Completer<void>? _tickDone;
  bool _dead = false, _busy = false, _published = false;
  String? _fingerprint;
  DateTime? _publishedAt;
  DateTime? _publishAfter;
  String? _publishWarning;
  Future<void> _saving = Future.value();
  bool get supported => _source.supported;
  String get _key => 'activity_${sha256.convert(utf8.encode(userId))}';

  Future<void> start() async {
    {
      try {
        settings = ActivitySettings.fromJson(
          jsonDecode(await _storage.read(key: _key) ?? '{}'),
        );
      } catch (_) {
        warning =
            'Activity preferences could not be restored. Sharing remains off.';
      }
    }
    if (_dead) return;
    notifyListeners();
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_tick()));
    await _tick();
  }

  UserActivity? activityFor(String id) {
    if (!_visible(id)) {
      _cache.remove(id);
      _recentCache.remove(id);
      _seen.remove(id);
      _fetched.remove(id);
      return null;
    }
    _seen[id] = DateTime.now();
    if (!(id == userId && _cache[id]?.expired == false) &&
        _foreground &&
        !_fetched.containsKey(id) &&
        !_busy &&
        !_dead &&
        _initialRead == null) {
      final remaining = _readAfter.difference(DateTime.now());
      _initialRead = Timer(
        remaining.isNegative ? const Duration(milliseconds: 150) : remaining,
        () {
          _initialRead = null;
          unawaited(_tick());
        },
      );
    }
    if (_seen.length > 64) {
      _seen.remove(_seen.keys.first);
    }
    final value = _cache[id];
    return value?.expired == false ? value : null;
  }

  LastFmTrack? lastFmRecentFor(String id) {
    if (id == userId &&
        (!settings.showLastFmRecent || !settings.share || !_foreground)) {
      return null;
    }
    activityFor(id); // Shares visibility, read scheduling and rate limits.
    final value = _recentCache[id];
    return _visible(id) &&
            value != null &&
            value.expiresAt.isAfter(DateTime.now())
        ? value.track
        : null;
  }

  Future<void> _writeRecord(
    UserActivity? activity, [
    LastFmTrack? recent,
  ]) async {
    // Recheck after asynchronous artwork work: disabling the footer or leaving
    // the foreground must not publish a captured Last.fm result afterwards.
    if (!settings.showLastFmRecent ||
        !publicLastFmApproved ||
        !settings.share ||
        !_foreground ||
        !canShare()) {
      recent = null;
    }
    if (writeProfile == null) {
      await write(activity);
      return;
    }
    final record =
        activity?.toJson() ??
        (recent == null
            ? null
            : <String, Object?>{
                'version': 1,
                'expires_at': DateTime.now()
                    .add(const Duration(minutes: 2))
                    .millisecondsSinceEpoch,
              });
    if (recent != null) record!['lastfm_recent'] = recent.toJson();
    await writeProfile!(record);
  }

  void _rememberRecent(LastFmTrack? track, DateTime expiry) {
    if (track == null ||
        !settings.showLastFmRecent ||
        !_foreground ||
        !canShare()) {
      _recentCache.remove(userId);
    } else {
      _recentCache[userId] = (track: track, expiresAt: expiry);
    }
  }

  Future<void> update(ActivitySettings value) async {
    // Opting out takes effect even if the device keyring is unavailable. The
    // caller still receives the persistence error, but publication must stop.
    if ((!value.detect && value.lastFmUser.isEmpty) ||
        !value.share ||
        (!value.showLastFmRecent && settings.showLastFmRecent)) {
      settings = value;
      if (!value.showLastFmRecent) _recentCache.remove(userId);
      notifyListeners();
      unawaited(_tick());
    }
    // Persist successfully before enabling detection/sharing.
    final next = _saving.catchError((Object _) {}).then((_) async {
      await _storage.write(key: _key, value: jsonEncode(value.toJson()));
      if (_dead) return;
      settings = value;
      notifyListeners();
    });
    _saving = next;
    await next;
    if (_busy) await _tickDone?.future;
    await _tick();
  }

  void refresh() => unawaited(_tick());

  /// Called on presence/lifecycle changes, including during an in-flight read.
  void visibilityChanged({bool refresh = true}) {
    _cache.removeWhere((id, _) => !_visible(id));
    _recentCache.removeWhere((id, _) => !_visible(id));
    _seen.removeWhere((id, _) => !_visible(id));
    _fetched.removeWhere((id, _) => !_visible(id));
    if (!_foreground) _lastFm.clear();
    if (refresh || !canShare()) this.refresh();
  }

  Future<void> _tick() async {
    if (_dead || _busy) return;
    final before = _uiSignature();
    _busy = true;
    _tickDone = Completer<void>();
    var stage = 'Local activity detection';
    try {
      {
        candidates = supported ? await _source.scan(settings) : [];
        LastFmTrack? recent;
        if (_foreground &&
            canShare() &&
            settings.share &&
            settings.lastFmUser.isNotEmpty &&
            (settings.showLastFmRecent ||
                !candidates.any(
                  (c) => c.running && c.kind == ActivityKind.music,
                ))) {
          final requestedUser = settings.lastFmUser;
          final lastFm = await _lastFm.scan(settings);
          if (_foreground &&
              canShare() &&
              settings.share &&
              requestedUser == settings.lastFmUser) {
            if (lastFm != null) candidates = [...candidates, lastFm];
            if (settings.showLastFmRecent && publicLastFmApproved) {
              recent = _lastFm.recent;
            }
          }
        }
        warning = _publishWarning ?? _source.warning;
        if (_dead) return;
        final eligible = candidates.where((c) {
          final rule = settings.rules[c.id];
          return c.running &&
              (c.lastFmUrl == null || _foreground) &&
              (rule?.allowed ?? (c.kind != null));
        });
        final chosen = _enabled && settings.share && canShare()
            ? eligible.firstOrNull
            : null;
        if (chosen == null) {
          final now = DateTime.now();
          final fingerprint = recent == null
              ? null
              : jsonEncode(['lastfm_recent', recent.toJson()]);
          if (recent != null &&
              (_publishAfter == null || !now.isBefore(_publishAfter!))) {
            if (fingerprint != _fingerprint ||
                _publishedAt == null ||
                now.difference(_publishedAt!) > heartbeat) {
              stage = 'Activity publication';
              await _writeRecord(
                null,
                recent,
              ).timeout(const Duration(seconds: 10));
              _rememberRecent(recent, now.add(const Duration(minutes: 2)));
              _published = true;
              _publishedAt = now;
              _fingerprint = fingerprint;
              _publishAfter = null;
              _publishWarning = null;
              warning = _source.warning;
            }
          } else if (recent == null &&
              _published &&
              (_publishAfter == null ||
                  !DateTime.now().isBefore(_publishAfter!))) {
            stage = 'Clearing shared activity';
            await _writeRecord(null).timeout(const Duration(seconds: 10));
            _published = false;
            _fingerprint = null;
            _publishAfter = null;
            _publishWarning = null;
          }
          _cache.remove(userId);
          if (recent == null) _recentCache.remove(userId);
        } else {
          final rule = settings.rules[chosen.id];
          final kind = rule?.kind ?? chosen.kind;
          if (kind != null) {
            final name = (rule?.name ?? chosen.name).trim();
            final digest = chosen.iconBytes == null
                ? ''
                : sha256.convert(chosen.iconBytes!).toString();
            final fingerprint = jsonEncode([
              chosen.id,
              kind.name,
              name,
              chosen.details,
              digest,
              recent?.toJson(),
            ]);
            final now = DateTime.now();
            final previousPlayback = _cache[userId]?.playback;
            final timingChanged =
                chosen.playback?.playing != previousPlayback?.playing ||
                chosen.playback?.durationMs != previousPlayback?.durationMs ||
                (chosen.playback != null &&
                    previousPlayback != null &&
                    (chosen.playback!.positionAt(now) -
                                previousPlayback.positionAt(now))
                            .abs() >
                        2500);
            // Explicit build override remains available if approval is revoked.
            if (chosen.lastFmUrl != null && !publicLastFmApproved) {
              if (_published) {
                stage = 'Clearing shared activity';
                await _writeRecord(null).timeout(const Duration(seconds: 10));
              }
              _published = false;
              _recentCache.remove(userId);
              _fingerprint = null;
              final current = _cache[userId];
              if (current?.name != name ||
                  current?.details != chosen.details ||
                  current?.lastFmUrl != chosen.lastFmUrl ||
                  current == null ||
                  current.expiresAt.difference(now) <
                      const Duration(minutes: 1)) {
                _cache[userId] = UserActivity(
                  kind: kind,
                  name: name,
                  details: chosen.details,
                  lastFmUrl: chosen.lastFmUrl,
                  expiresAt: now.add(const Duration(minutes: 2)),
                );
              }
              warning =
                  'Public Last.fm sharing is disabled by this build; this preview is local only.';
            } else if (_publishAfter == null || !now.isBefore(_publishAfter!)) {
              if (fingerprint != _fingerprint ||
                  timingChanged ||
                  _publishedAt == null ||
                  now.difference(_publishedAt!) > heartbeat) {
                Uri? icon = _icons[digest];
                if (icon == null && chosen.iconBytes != null) {
                  stage = 'Activity artwork upload';
                  icon = await upload(
                    chosen.iconBytes!,
                  ).timeout(const Duration(seconds: 10));
                  if (_icons.length >= 32) _icons.remove(_icons.keys.first);
                  _icons[digest] = icon;
                }
                if (_dead ||
                    !_enabled ||
                    !settings.share ||
                    !canShare() ||
                    settings.rules[chosen.id]?.allowed == false) {
                  return;
                }
                final value = UserActivity(
                  kind: kind,
                  name: name.substring(0, name.length.clamp(0, 128)),
                  details: chosen.details,
                  icon: icon,
                  startedAt:
                      _cache[userId]?.kind == kind &&
                          _cache[userId]?.name == name &&
                          _cache[userId]?.details == chosen.details
                      ? _cache[userId]?.startedAt
                      : now,
                  expiresAt: now.add(const Duration(minutes: 2)),
                  playback: chosen.playback,
                  lastFmUrl: chosen.lastFmUrl,
                );
                stage = 'Activity publication';
                await _writeRecord(
                  value,
                  recent,
                ).timeout(const Duration(seconds: 10));
                _cache[userId] = value;
                _rememberRecent(recent, value.expiresAt);
                _published = true;
                _fingerprint = fingerprint;
                _publishedAt = now;
                _publishAfter = null;
                _publishWarning = null;
                warning = _source.warning;
              }
            }
          }
        }
      }
      final now = DateTime.now();
      _seen.removeWhere(
        (_, at) => now.difference(at) > const Duration(minutes: 2),
      );
      final users = _seen.keys
          .where(
            (id) => _foreground && _visible(id) && !now.isBefore(_readAfter),
          )
          .where(
            (id) =>
                id != userId || (!_published && _cache[id]?.expired != false),
          )
          .where(
            (id) =>
                _fetched[id] == null ||
                now.difference(_fetched[id]!) >= const Duration(seconds: 40),
          )
          .toList();
      users.sort(
        (a, b) => (_fetched[a]?.millisecondsSinceEpoch ?? 0).compareTo(
          _fetched[b]?.millisecondsSinceEpoch ?? 0,
        ),
      );
      // Profile GETs share homeserver rate limits with startup/profile loading.
      // No fan-out: at most eight per pass, one per second, and pause the entire
      // activity reader after any error rather than hammering other profiles.
      for (final id in users.take(8)) {
        if (_dead || !_foreground) break;
        if (!_visible(id)) continue;
        _fetched[id] = DateTime.now();
        try {
          final record = await read(id).timeout(const Duration(seconds: 8));
          if (!_dead && _foreground && _visible(id)) {
            _cache[id] = UserActivity.fromJson(record);
            final expiry = activityRecordExpiry(record);
            final track = record is Map
                ? LastFmTrack.fromJson(record['lastfm_recent'])
                : null;
            if (expiry != null && track != null) {
              _recentCache[id] = (track: track, expiresAt: expiry);
            } else {
              _recentCache.remove(id);
            }
          }
        } on ActivityServiceError catch (error) {
          if (error.code == 'M_NOT_FOUND') {
            _cache.remove(id);
            _recentCache.remove(id);
            continue;
          }
          _readAfter = DateTime.now().add(
            error.retryAfter ?? const Duration(minutes: 1),
          );
          break;
        } catch (_) {
          _readAfter = DateTime.now().add(const Duration(minutes: 1));
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      _cache.removeWhere(
        (id, value) =>
            id != userId && (!_seen.containsKey(id) || value?.expired == true),
      );
      _fetched.removeWhere((id, _) => !_seen.containsKey(id));
    } catch (error) {
      final code = error is ActivityServiceError ? error.code : null;
      warning = switch (code) {
        'M_LIMIT_EXCEEDED' =>
          'Activity publication is rate-limited by the homeserver; retrying automatically.',
        'M_FORBIDDEN' || 'M_UNRECOGNIZED' || 'M_INVALID_PARAM' =>
          'The homeserver rejected activity profile updates ($code).',
        'M_UNKNOWN_TOKEN' || 'M_MISSING_TOKEN' =>
          'Activity sharing is waiting for a valid signed-in session.',
        _ =>
          '$stage failed (${error.runtimeType}). Retrying automatically; this does not necessarily indicate an internet problem.',
      };
      if (stage != 'Local activity detection') {
        final retry = error is ActivityServiceError ? error.retryAfter : null;
        _publishAfter = DateTime.now().add(
          retry ?? const Duration(seconds: 30),
        );
        _publishWarning = warning;
      }
    } finally {
      _cache.removeWhere((_, value) => value?.expired == true);
      _recentCache.removeWhere(
        (id, value) =>
            !_visible(id) ||
            !value.expiresAt.isAfter(DateTime.now()) ||
            (id != userId && !_seen.containsKey(id)),
      );
      _busy = false;
      _tickDone?.complete();
      if (!_dead && before != _uiSignature()) notifyListeners();
    }
    // Settings can change during an asynchronous scan. Never leave disabled
    // sharing active until the next polling interval.
    if (!_dead &&
        _published &&
        (_publishAfter == null || !DateTime.now().isBefore(_publishAfter!)) &&
        (!_enabled || !settings.share || !canShare())) {
      unawaited(_tick());
    }
  }

  Future<void> close({bool clear = false}) async {
    _dead = true;
    _timer?.cancel();
    _initialRead?.cancel();
    await _source.dispose();
    if (_busy) await _tickDone?.future;
    if (clear && _published) {
      try {
        await _writeRecord(null);
      } catch (_) {}
    }
    dispose();
  }

  String _uiSignature() => jsonEncode([
    warning,
    candidates.map((c) => [c.id, c.name, c.kind?.name, c.details]).toList(),
    _cache.map((id, activity) => MapEntry(id, activity?.toJson())),
    _recentCache.map(
      (id, recent) => MapEntry(id, [
        recent.track.toJson(),
        recent.expiresAt.millisecondsSinceEpoch,
      ]),
    ),
  ]);
}
