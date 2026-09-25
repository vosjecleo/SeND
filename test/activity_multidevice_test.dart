import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_controller.dart';
import 'package:deltiecord/services/activity_source.dart';
import 'package:deltiecord/services/lastfm_activity.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'widget_test.dart' show FakeBackend;

class Source extends DesktopActivitySource {
  List<ActivityCandidate> values = [];
  @override
  bool get supported => true;
  @override
  Future<List<ActivityCandidate>> scan(ActivitySettings settings) async =>
      values;
  @override
  Future<void> dispose() async {}
}

final recentTrack = LastFmTrack(
  name: 'Completed song',
  artist: 'Artist',
  album: 'Album',
  url: Uri.parse('https://www.last.fm/music/Artist/_/Song'),
  playedAt: DateTime.now().subtract(const Duration(minutes: 5)),
);

class Feed extends LastFmActivitySource {
  @override
  Future<ActivityCandidate?> scan(ActivitySettings settings) async {
    recent = recentTrack;
    return null;
  }
}

class MultiBackend extends FakeBackend {
  @override
  List<UserActivity> activitiesFor(String id) => [
    for (final kind in [ActivityKind.game, ActivityKind.music])
      UserActivity(
        kind: kind,
        name: kind.name,
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      ),
  ];
  @override
  LastFmTrack? lastFmRecentFor(String id) => recentTrack;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'different-account viewer fetches all slots without sharing or Last.fm login',
    () async {
      var online = true;
      final reads = <String>[];
      final activity = UserActivity(
        kind: ActivityKind.game,
        name: 'Remote game',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
      final music = UserActivity(
        kind: ActivityKind.music,
        name: 'Remote song',
        expiresAt: activity.expiresAt,
      );
      final viewer = ActivityController(
        userId: '@viewer:test',
        deviceId: 'viewer',
        source: Source(),
        canShare: () => false,
        canView: (_) => online,
        read: (id) async {
          reads.add(id);
          return {
            'devices': {
              activityDeviceField('desktop'): {
                ...activity.toJson(),
                'slots': {
                  'program': activity.toJson(),
                  'music': music.toJson(),
                },
                'lastfm_recent': recentTrack.toJson(),
              },
            },
          };
        },
        write: (_) async => fail('Viewing must not publish'),
        upload: (_) async => throw StateError('Viewing must not upload'),
        pollInterval: const Duration(days: 1),
        readStartDelay: Duration.zero,
      );
      addTearDown(viewer.close);
      await viewer.start();
      expect(viewer.activitiesFor('@publisher:test').live, isEmpty);
      await viewer.update(viewer.settings);
      expect(reads, ['@publisher:test']);
      final result = viewer.activitiesFor('@publisher:test');
      expect(result.program?.name, 'Remote game');
      expect(result.music?.name, 'Remote song');
      expect(result.recent?.name, 'Completed song');
      online = false;
      viewer.visibilityChanged(refresh: false);
      expect(viewer.activitiesFor('@publisher:test').live, isEmpty);
      expect(viewer.lastFmRecentFor('@publisher:test'), isNull);
      online = true;
      viewer.activitiesFor('@publisher:test');
      await viewer.update(viewer.settings);
      expect(reads.length, 2);
      expect(viewer.lastFmRecentFor('@publisher:test')?.name, 'Completed song');
    },
  );

  test(
    'desktop game/music and phone history coexist; clearing one device leaves others',
    () async {
      final records = <String, Object?>{};
      final sources = [Source(), Source(), Source()];
      final visible = [true, true, true];
      final controllers = <ActivityController>[];
      for (var i = 0; i < 3; i++) {
        final controller = ActivityController(
          userId: '@me:test',
          deviceId: 'device$i',
          source: sources[i],
          lastFm: Feed(),
          canShare: () => visible[i],
          canView: (_) => true,
          read: (_) async => {'devices': Map<String, Object?>.from(records)},
          write: (_) async => fail('Use device-owned profile records'),
          writeProfile: (value) async {
            records[activityDeviceField('device$i')] = value;
          },
          upload: (Uint8List _) async => Uri.parse('mxc://test/art'),
          pollInterval: const Duration(days: 1),
          readInterval: Duration.zero,
          readStartDelay: Duration.zero,
        );
        controllers.add(controller);
        addTearDown(controller.close);
        await controller.start();
      }
      sources[0].values = [
        const ActivityCandidate(
          id: 'game',
          name: 'Game',
          kind: ActivityKind.game,
        ),
        const ActivityCandidate(
          id: 'player',
          name: 'Native song',
          kind: ActivityKind.music,
        ),
      ];
      await controllers[0].update(
        const ActivitySettings(detect: true, share: true),
      );
      await controllers[1].update(
        const ActivitySettings(
          share: true,
          lastFmUser: 'user',
          lastFmKey: 'key',
          showLastFmRecent: true,
        ),
      );
      for (final controller in controllers) {
        controller.activitiesFor('@me:test');
        await controller.update(controller.settings);
        final view = controller.activitiesFor('@me:test');
        expect(view.program?.name, 'Game');
        expect(view.music?.name, 'Native song');
        expect(view.recent?.name, 'Completed song');
      }
      // Phone background/opt-out must never delete the desktop's publication.
      visible[1] = false;
      await controllers[1].update(controllers[1].settings);
      expect(UserActivities.fromRecords(records).program?.name, 'Game');
      expect(UserActivities.fromRecords(records).music?.name, 'Native song');
      expect(UserActivities.fromRecords(records).recent, isNull);
      // A viewing-only phone still reads the desktop, despite sharing being off.
      await controllers[2].update(controllers[2].settings);
      expect(controllers[2].activitiesFor('@me:test').live.length, 2);
      await controllers[0].update(
        controllers[0].settings.copyWith(share: false),
      );
      expect(UserActivities.fromRecords(records).live, isEmpty);
    },
  );

  test(
    'native music wins over newer Last.fm; expired and wrong-kind slots ignored',
    () {
      final now = DateTime.now();
      Map<String, Object?> record(
        String name, {
        bool lastfm = false,
        bool expired = false,
      }) {
        final a = UserActivity(
          kind: ActivityKind.music,
          name: name,
          expiresAt: now.add(
            Duration(
              seconds: expired
                  ? -1
                  : lastfm
                  ? 100
                  : 60,
            ),
          ),
          lastFmUrl: lastfm ? recentTrack.url : null,
        );
        return {
          ...a.toJson(),
          'slots': {'music': a.toJson(), 'program': a.toJson()},
        };
      }

      final result = UserActivities.fromRecords({
        'native': record('Native'),
        'fm': record('FM', lastfm: true),
        'old': record('Expired', expired: true),
      });
      expect(result.music?.name, 'Native');
      expect(result.program, isNull);
      expect(
        UserActivities.fromRecords({
          'old': record('Expired', expired: true),
        }).live,
        isEmpty,
      );
    },
  );

  testWidgets(
    'profile shows game and music together with separate recent footer',
    (tester) async {
      final backend = MultiBackend();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: ActivityScope(
            backend: backend,
            child: const Scaffold(
              body: Column(
                children: [
                  ActivityBlock(userId: '@me:test'),
                  LastFmRecentBar(userId: '@me:test'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Currently playing:'), findsOneWidget);
      expect(find.text('Currently listening to:'), findsOneWidget);
      expect(find.text('Completed song'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
