import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/activity_controller.dart';
import 'package:deltiecord/services/activity_service_error.dart';
import 'package:deltiecord/services/lastfm_activity.dart';
import 'activity_multidevice_test.dart' show Source, Feed, recentTrack;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'history publication errors back off without blocking live updates',
    () async {
      var attempts = 0;
      Map<String, Object?>? live;
      final controller = ActivityController(
        userId: '@me:test',
        source: Source(),
        lastFm: Feed(),
        pollInterval: const Duration(days: 1),
        canShare: () => true,
        read: (_) async => null,
        write: (_) async {},
        writeProfile: (record) async => live = record,
        writeHistory: (record) async {
          if (record == null) return;
          attempts++;
          throw const ActivityServiceError(
            'M_LIMIT_EXCEEDED',
            retryAfter: Duration(minutes: 1),
          );
        },
        upload: (_) async => Uri.parse('mxc://test/icon'),
      );
      addTearDown(controller.close);
      await controller.start();
      await controller.update(
        const ActivitySettings(
          share: true,
          lastFmUser: 'user',
          lastFmKey: 'key',
          showLastFmRecent: true,
        ),
      );
      expect(attempts, 1);
      expect(live?['lastfm_recent'], isNotNull);
      await controller.update(controller.settings);
      expect(attempts, 1);
      expect(controller.warning, contains('history'));
    },
  );
  test('real Last.fm CDN artwork accepted for completed and live songs', () {
    const art = 'https://lastfm-img.freetls.fastly.net/i/u/300x300/cover.jpg';
    final value = <String, Object?>{
      'name': 'Track',
      'artist': {'#text': 'Artist'},
      'album': {'#text': 'Album'},
      'date': {'uts': '1700000000'},
      'image': [
        {
          'size': 'small',
          '#text': 'https://lastfm-img.freetls.fastly.net/i/u/34s/cover.jpg',
        },
        {'size': 'extralarge', '#text': art},
      ],
    };
    final recent = lastFmRecentlyPlayed({
      'recenttracks': {
        'track': [value],
      },
    }, 'user')!;
    expect(recent.artwork.toString(), art);
    expect(LastFmTrack.fromJson(recent.toJson())!.artwork.toString(), art);
    final live = lastFmNowPlaying({
      'recenttracks': {
        'track': [
          {
            ...value,
            '@attr': {'nowplaying': 'true'},
          },
        ],
      },
    }, 'user');
    expect(live!.lastFmArtwork.toString(), art);
    expect(
      validLastFmArtwork(
        'https://lastfm-img.freetls.fastly.net.evil.test/i/u/a.jpg',
      ),
      isNull,
    );
  });
  test(
    'history persists after close and is fetched offline by another account',
    () async {
      final records = <String, Object?>{};
      var online = true;
      final publisher = ActivityController(
        userId: '@publisher:test',
        deviceId: 'desktop',
        source: Source(),
        lastFm: Feed(),
        pollInterval: const Duration(days: 1),
        canShare: () => online,
        canView: (_) => online,
        read: (_) async => null,
        write: (_) async {},
        writeProfile: (value) async =>
            records[activityDeviceField('desktop')] = value,
        writeHistory: (value) async =>
            records[lastFmHistoryField('desktop')] = value,
        upload: (_) async => Uri.parse('mxc://test/icon'),
      );
      await publisher.start();
      await publisher.update(
        const ActivitySettings(
          share: true,
          lastFmUser: 'user',
          lastFmKey: 'key',
          showLastFmRecent: true,
        ),
      );
      expect(
        UserActivities.fromRecords(records).recent?.name,
        'Completed song',
      );
      online = false;
      await publisher.update(publisher.settings);
      expect(
        publisher.lastFmRecentFor('@publisher:test')?.name,
        'Completed song',
      );
      await publisher.close();
      expect(
        UserActivities.fromRecords(records).recent?.name,
        'Completed song',
      );
      final viewer = ActivityController(
        userId: '@viewer:test',
        source: Source(),
        pollInterval: const Duration(days: 1),
        readStartDelay: Duration.zero,
        canShare: () => false,
        canView: (_) => false,
        read: (_) async => {'devices': records},
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
      );
      addTearDown(viewer.close);
      await viewer.start();
      viewer.lastFmRecentFor('@publisher:test');
      await viewer.update(viewer.settings);
      expect(viewer.lastFmRecentFor('@publisher:test')?.name, 'Completed song');
      expect(viewer.activitiesFor('@publisher:test').live, isEmpty);
    },
  );
  test(
    'history survives lease expiry and explicit opt-out removes only own device',
    () async {
      final records = <String, Object?>{
        lastFmHistoryField('phone'): {
          'version': 1,
          'track': recentTrack.toJson(),
        },
        activityDeviceField('expired'): {
          'version': 1,
          'expires_at': 1,
          'name': 'Old live song',
        },
      };
      final controller = ActivityController(
        userId: '@me:test',
        deviceId: 'desktop',
        source: Source(),
        lastFm: Feed(),
        pollInterval: const Duration(days: 1),
        canShare: () => true,
        read: (_) async => null,
        write: (_) async {},
        writeHistory: (value) async =>
            records[lastFmHistoryField('desktop')] = value,
        upload: (_) async => Uri.parse('mxc://test/icon'),
      );
      addTearDown(controller.close);
      await controller.start();
      await controller.update(
        const ActivitySettings(
          share: true,
          lastFmUser: 'user',
          lastFmKey: 'key',
          showLastFmRecent: true,
        ),
      );
      await controller.update(
        controller.settings.copyWith(showLastFmRecent: false),
      );
      expect(records[lastFmHistoryField('desktop')], isNull);
      expect(
        UserActivities.fromRecords(records).recent?.name,
        'Completed song',
      );
      expect(UserActivities.fromRecords(records).live, isEmpty);
    },
  );
}
