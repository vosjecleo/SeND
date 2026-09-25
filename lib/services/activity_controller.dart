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

/// Bounded profile polling with independently owned device publications.
class ActivityController extends ChangeNotifier {
  ActivityController({
    required this.userId,
    this.deviceId = 'local',
    required this.read,
    required this.write,
    this.writeProfile,
    this.writeHistory,
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
    this.readInterval = const Duration(seconds: 40),
    Duration readStartDelay = const Duration(seconds: 15),
  }) : _source = source ?? DesktopActivitySource(),
       _lastFm = lastFm ?? LastFmActivitySource(),
       _readAfter = DateTime.now().add(readStartDelay),
       _storage = storage ?? const FlutterSecureStorage();
  final String userId, deviceId;
  final Future<Object?> Function(String) read;
  final Future<void> Function(UserActivity?) write;
  final Future<void> Function(Map<String, Object?>?)? writeProfile;
  final Future<void> Function(Map<String, Object?>?)? writeHistory;
  final Future<Uri> Function(Uint8List) upload;
  final bool Function() canShare;
  final bool Function(String)? canView;
  final bool Function()? isForeground;
  final bool publicLastFmApproved;
  final LastFmActivitySource _lastFm;
  final DesktopActivitySource _source;
  final FlutterSecureStorage _storage;
  final Duration pollInterval, heartbeat, readInterval;
  final _seen = <String, DateTime>{};
  final _historyWatch = <String>{};
  final _fetched = <String, DateTime>{};
  final _observedOnline = <String, bool>{};
  final _records = <String, Map<String, Object?>>{};
  final _icons = <String, Uri>{};
  Map<String, Object?>? _local;
  bool _localOwned = false;
  Map<String, Object?>? _localHistory;
  bool _historyOwned = false;
  String? _historyFingerprint;
  DateTime? _historyAfter;
  String? _historyWarning;
  DateTime _readAfter;
  ActivitySettings settings = const ActivitySettings();
  List<ActivityCandidate> candidates = const [];
  String? warning;
  Timer? _timer, _initialRead;
  Completer<void>? _tickDone;
  bool _dead = false, _busy = false, _published = false;
  String? _fingerprint, _publishWarning;
  String? _lastUi;
  DateTime? _publishedAt, _publishAfter;
  Future<void> _saving = Future.value();
  bool get supported => _source.supported;
  bool get _foreground => isForeground?.call() ?? true;
  bool _visible(String id) => canView?.call(id) ?? true;
  String get _field => activityDeviceField(deviceId);
  String get _key => 'activity_${sha256.convert(utf8.encode(userId))}';

  Future<void> start() async {
    try {
      settings = ActivitySettings.fromJson(
        jsonDecode(await _storage.read(key: _key) ?? '{}'),
      );
    } catch (_) {
      warning =
          'Activity preferences could not be restored. Sharing remains off.';
    }
    if (_dead) return;
    notifyListeners();
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_tick()));
    await _tick();
  }

  UserActivities activitiesFor(String id) {
    if (!_visible(id)) {
      return _combined(id);
    }
    _observe(id);
    return _combined(id);
  }

  void _observe(String id) {
    final online = _visible(id);
    if (_observedOnline[id] != online) _fetched.remove(id);
    _observedOnline[id] = online;
    _seen[id] = DateTime.now();
    if (_seen.length > 64) _seen.remove(_seen.keys.first);
    if (_foreground &&
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
  }

  UserActivities _combined(String id) {
    final records = {...?_records[id]};
    if (id == userId && _localOwned) records[_field] = _local;
    if (id == userId && _historyOwned) {
      records[lastFmHistoryField(deviceId)] = _localHistory;
    }
    if (id == userId &&
        writeHistory != null &&
        (!settings.share ||
            !settings.showLastFmRecent ||
            settings.lastFmUser.isEmpty)) {
      records.remove(lastFmHistoryField(deviceId));
    }
    if (!_visible(id)) {
      records.removeWhere((key, _) => !key.startsWith(lastFmHistoryPrefix));
    }
    return UserActivities.fromRecords(records);
  }

  UserActivity? activityFor(String id) => activitiesFor(id).primary;
  LastFmTrack? lastFmRecentFor(String id) {
    _historyWatch.add(id);
    _observe(id);
    return _combined(id).recent;
  }

  Future<void> update(ActivitySettings value) async {
    // Revocations take effect even if secure storage fails, and during uploads.
    if (!value.share ||
        (!value.detect && value.lastFmUser.isEmpty) ||
        (!value.showLastFmRecent && settings.showLastFmRecent)) {
      settings = value;
      _local = null;
      _localOwned = true;
      notifyListeners();
      unawaited(_tick());
    }
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
  void visibilityChanged({bool refresh = true}) {
    for (final entry in _records.entries) {
      if (!_visible(entry.key)) {
        if (_observedOnline[entry.key] != false) _fetched.remove(entry.key);
        _observedOnline[entry.key] = false;
        entry.value.removeWhere(
          (key, _) => !key.startsWith(lastFmHistoryPrefix),
        );
      }
    }
    if (!_foreground) _lastFm.suspend();
    if (refresh || !canShare()) this.refresh();
  }

  bool _eligible(ActivityCandidate c) =>
      c.running &&
      (c.lastFmUrl == null
          ? settings.detect
          : _foreground &&
                (settings.detect || settings.lastFmUser.isNotEmpty)) &&
      (settings.rules[c.id]?.allowed ?? (c.kind != null));

  Future<UserActivity> _materialize(
    ActivityCandidate chosen,
    UserActivity? previous,
    DateTime now,
  ) async {
    final rule = settings.rules[chosen.id];
    final name = (rule?.name ?? chosen.name).trim();
    final kind = rule?.kind ?? chosen.kind!;
    Uri? icon;
    if (chosen.iconBytes != null) {
      final digest = sha256.convert(chosen.iconBytes!).toString();
      icon = _icons[digest];
      if (icon == null) {
        icon = await upload(
          chosen.iconBytes!,
        ).timeout(const Duration(seconds: 10));
        if (_icons.length >= 32) _icons.remove(_icons.keys.first);
        _icons[digest] = icon;
      }
    }
    return UserActivity(
      kind: kind,
      name: name.substring(0, name.length.clamp(0, 128)),
      details: chosen.details,
      icon: icon,
      startedAt:
          previous?.kind == kind &&
              previous?.name == name &&
              previous?.details == chosen.details
          ? previous?.startedAt
          : now,
      expiresAt: now.add(const Duration(minutes: 2)),
      playback: chosen.playback,
      lastFmUrl: chosen.lastFmUrl,
      lastFmArtwork: chosen.lastFmArtwork,
    );
  }

  Future<void> _publish(Map<String, Object?>? record) async {
    if (writeProfile != null) {
      await writeProfile!(record).timeout(const Duration(seconds: 10));
    } else {
      await write(
        UserActivity.fromJson(record),
      ).timeout(const Duration(seconds: 10));
    }
    _local = record;
    _localOwned = true;
    _published = record != null;
  }

  Future<void> _tick() async {
    if (_dead || _busy) return;
    _busy = true;
    _tickDone = Completer<void>();
    var stage = 'Local activity detection';
    try {
      candidates = supported ? await _source.scan(settings) : [];
      LastFmTrack? recent;
      if (_foreground &&
          canShare() &&
          settings.share &&
          settings.lastFmUser.isNotEmpty &&
          (settings.showLastFmRecent ||
              !candidates.any(
                (c) =>
                    _eligible(c) &&
                    (settings.rules[c.id]?.kind ?? c.kind) ==
                        ActivityKind.music,
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
      if (_dead) return;
      // Last-listened history is durable public metadata, not live presence.
      // Close/background/offline must not clear it. Explicit opt-out clears
      // only this device's contribution; other linked devices stay independent.
      if (writeHistory != null &&
          (_historyAfter == null || !DateTime.now().isBefore(_historyAfter!))) {
        final enabled =
            settings.share &&
            settings.showLastFmRecent &&
            settings.lastFmUser.isNotEmpty &&
            publicLastFmApproved;
        final nextHistory = enabled && recent != null
            ? <String, Object?>{'version': 1, 'track': recent.toJson()}
            : null;
        final fingerprint = nextHistory == null
            ? null
            : jsonEncode(nextHistory);
        if ((!enabled && (!_historyOwned || _localHistory != null)) ||
            (nextHistory != null && fingerprint != _historyFingerprint)) {
          try {
            await writeHistory!(
              nextHistory,
            ).timeout(const Duration(seconds: 10));
            _localHistory = nextHistory;
            _historyOwned = true;
            _historyFingerprint = fingerprint;
            _historyAfter = null;
            _historyWarning = null;
          } catch (error) {
            _historyAfter = DateTime.now().add(
              error is ActivityServiceError
                  ? error.retryAfter ?? const Duration(seconds: 30)
                  : const Duration(seconds: 30),
            );
            _historyWarning =
                'Last.fm history could not be ${enabled ? 'saved' : 'removed'}; retrying automatically.';
            // A history outage must not block live publishing or viewing.
          }
        }
      }
      warning = _publishWarning ?? _historyWarning ?? _source.warning;
      final eligible = settings.share && canShare()
          ? candidates.where(_eligible).toList()
          : <ActivityCandidate>[];
      final program = eligible
          .where(
            (c) => (settings.rules[c.id]?.kind ?? c.kind) != ActivityKind.music,
          )
          .firstOrNull;
      final musicCandidates = eligible.where(
        (c) => (settings.rules[c.id]?.kind ?? c.kind) == ActivityKind.music,
      );
      final music =
          musicCandidates.where((c) => c.lastFmUrl == null).firstOrNull ??
          musicCandidates.firstOrNull;
      final chosen = [?program, ?music];
      final now = DateTime.now();
      final fingerprint = chosen.isEmpty && recent == null
          ? null
          : jsonEncode([
              for (final c in chosen)
                [
                  c.id,
                  (settings.rules[c.id]?.kind ?? c.kind)?.name,
                  settings.rules[c.id]?.name ?? c.name,
                  c.details,
                  c.iconBytes == null
                      ? ''
                      : sha256.convert(c.iconBytes!).toString(),
                  c.lastFmUrl?.toString(),
                  c.lastFmArtwork?.toString(),
                ],
              recent?.toJson(),
            ]);
      final previous = UserActivities.fromRecords({_field: _local});
      final playback = music?.playback, oldPlayback = previous.music?.playback;
      final timingChanged =
          playback?.playing != oldPlayback?.playing ||
          playback?.durationMs != oldPlayback?.durationMs ||
          (playback != null &&
              oldPlayback != null &&
              (playback.positionAt(now) - oldPlayback.positionAt(now)).abs() >
                  2500);
      if (_publishAfter == null || !now.isBefore(_publishAfter!)) {
        if (fingerprint != _fingerprint ||
            timingChanged ||
            (fingerprint != null &&
                (_publishedAt == null ||
                    now.difference(_publishedAt!) > heartbeat)) ||
            (fingerprint == null && _published)) {
          stage = 'Activity artwork upload';
          final p = program == null
              ? null
              : await _materialize(program, previous.program, now);
          final m = music == null
              ? null
              : await _materialize(music, previous.music, now);
          // A settings/lifecycle change during upload must not leak stale data.
          if (_dead ||
              (chosen.isNotEmpty &&
                  (!settings.share ||
                      !canShare() ||
                      chosen.any((c) => !_eligible(c))))) {
            return;
          }
          if (!settings.showLastFmRecent ||
              !_foreground ||
              !canShare() ||
              !settings.share) {
            recent = null;
          }
          final publicMusic = m?.lastFmUrl != null && !publicLastFmApproved
              ? null
              : m;
          final primary = p ?? publicMusic;
          final record = primary == null && recent == null
              ? null
              : <String, Object?>{
                  ...?primary?.toJson(),
                  'version': 1,
                  'expires_at': now
                      .add(const Duration(minutes: 2))
                      .millisecondsSinceEpoch,
                  'slots': {
                    'program': p?.toJson(),
                    'music': publicMusic?.toJson(),
                  },
                  if (recent != null) 'lastfm_recent': recent.toJson(),
                };
          stage = 'Activity publication';
          if (record != null || _published) await _publish(record);
          if (m != null && publicMusic == null) {
            // Explicit unapproved-build mode stays local only.
            _local = {
              ...m.toJson(),
              'slots': {'program': p?.toJson(), 'music': m.toJson()},
            };
            _localOwned = true;
            warning =
                'Public Last.fm sharing is disabled by this build; this preview is local only.';
          } else {
            warning = _source.warning;
          }
          _fingerprint = fingerprint;
          _publishedAt = now;
          _publishAfter = null;
          _publishWarning = null;
        }
      }
      _seen.removeWhere(
        (_, at) => now.difference(at) > const Duration(minutes: 2),
      );
      _historyWatch.removeWhere((id) => !_seen.containsKey(id));
      final users = _seen.keys
          .where(
            (id) =>
                _foreground &&
                (_visible(id) || _historyWatch.contains(id)) &&
                !now.isBefore(_readAfter) &&
                (_fetched[id] == null ||
                    now.difference(_fetched[id]!) >= readInterval),
          )
          .toList();
      users.sort(
        (a, b) => (_fetched[a]?.millisecondsSinceEpoch ?? 0).compareTo(
          _fetched[b]?.millisecondsSinceEpoch ?? 0,
        ),
      );
      for (final id in users.take(8)) {
        if (_dead || !_foreground) break;
        if (!_visible(id) && !_historyWatch.contains(id)) continue;
        _fetched[id] = DateTime.now();
        try {
          final response = await read(id).timeout(const Duration(seconds: 8));
          if (!_dead &&
              _foreground &&
              (_visible(id) || _historyWatch.contains(id))) {
            _records[id] = response is Map && response['devices'] is Map
                ? Map<String, Object?>.from(response['devices'] as Map)
                : {activityProfileField: response};
            if (!_visible(id)) {
              _records[id]!.removeWhere(
                (key, _) => !key.startsWith(lastFmHistoryPrefix),
              );
            }
          }
        } on ActivityServiceError catch (error) {
          if (error.code == 'M_NOT_FOUND') {
            _records.remove(id);
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
      _records.removeWhere((id, _) => !_seen.containsKey(id));
      _fetched.removeWhere((id, _) => !_seen.containsKey(id));
      _observedOnline.removeWhere((id, _) => !_seen.containsKey(id));
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
        _publishAfter = DateTime.now().add(
          error is ActivityServiceError
              ? error.retryAfter ?? const Duration(seconds: 30)
              : const Duration(seconds: 30),
        );
        _publishWarning = warning;
      }
    } finally {
      _busy = false;
      _tickDone?.complete();
      final signature = _uiSignature();
      if (!_dead && _lastUi != signature) {
        _lastUi = signature;
        notifyListeners();
      }
    }
    if (!_dead &&
        _published &&
        (_publishAfter == null || !DateTime.now().isBefore(_publishAfter!)) &&
        (!settings.share ||
            !canShare() ||
            (!settings.detect && settings.lastFmUser.isEmpty))) {
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
        await _publish(null);
      } catch (_) {}
    }
    dispose();
  }

  String _uiSignature() => jsonEncode([
    warning,
    candidates.map((c) => [c.id, c.name, c.kind?.name, c.details]).toList(),
    for (final id in {..._seen.keys, userId})
      [
        id,
        _combined(id).live.map((a) => a.toJson()).toList(),
        _combined(id).recent?.toJson(),
      ],
  ]);
}
