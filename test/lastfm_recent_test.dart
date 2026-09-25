import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_controller.dart';
import 'package:deltiecord/services/activity_source.dart';
import 'package:deltiecord/services/lastfm_activity.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'widget_test.dart' show FakeBackend;

LastFmTrack track() => LastFmTrack(
  name: 'Track',
  artist: 'Artist',
  album: 'Album',
  url: Uri.parse('https://www.last.fm/music/Artist/_/Track'),
  playedAt: DateTime.now().subtract(const Duration(minutes: 5)),
);

class Games extends DesktopActivitySource {
  bool playing = false;
  @override
  bool get supported => true;
  @override
  Future<List<ActivityCandidate>> scan(ActivitySettings settings) async =>
      playing && settings.detect
      ? [
          const ActivityCandidate(
            id: 'game',
            name: 'Game',
            kind: ActivityKind.game,
          ),
        ]
      : [];
  @override
  Future<void> dispose() async {}
}

class Feed extends LastFmActivitySource {
  @override
  Future<ActivityCandidate?> scan(ActivitySettings settings) async {
    recent = track();
    return null;
  }
}

class ProfileBackend extends FakeBackend {
  LastFmTrack? recent = track();
  @override
  LastFmTrack? lastFmRecentFor(String id) => recent;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'approval is enabled; recent track stays opt-in and settings round trip',
    () {
      expect(lastFmPublicDisplayApproved, isTrue);
      expect(const ActivitySettings().showLastFmRecent, isFalse);
      final settings = const ActivitySettings().copyWith(
        showLastFmRecent: true,
      );
      expect(
        ActivitySettings.fromJson(settings.toJson()).showLastFmRecent,
        isTrue,
      );
      expect(
        ActivitySettings.fromJson({'detect': true}).showLastFmRecent,
        isFalse,
      );
    },
  );

  test('parser skips currently playing and keeps completed track album', () {
    final value = lastFmRecentlyPlayed({
      'recenttracks': {
        'track': [
          {
            'name': 'Playing',
            '@attr': {'nowplaying': 'true'},
          },
          {
            'name': 'Track',
            'artist': {'#text': 'Artist'},
            'album': {'#text': 'Album'},
            'date': {
              'uts':
                  '${DateTime.now().subtract(const Duration(minutes: 4)).millisecondsSinceEpoch ~/ 1000}',
            },
            'url': 'https://www.last.fm/music/Artist/_/Track',
          },
        ],
      },
    }, 'user');
    expect(value?.name, 'Track');
    expect(value?.artist, 'Artist');
    expect(value?.album, 'Album');
    expect(
      lastFmRecentlyPlayed({
        'recenttracks': {
          'track': [
            {'name': 'Undated'},
          ],
        },
      }, 'user'),
      isNull,
    );
  });

  test(
    'recent metadata validates URL, text lengths, timestamp and record lease',
    () {
      final value = track();
      expect(LastFmTrack.fromJson(value.toJson())?.album, 'Album');
      expect(
        LastFmTrack.fromJson({...value.toJson(), 'url': 'javascript:alert(1)'}),
        isNull,
      );
      expect(
        LastFmTrack.fromJson({...value.toJson(), 'name': 'x' * 129}),
        isNull,
      );
      expect(
        LastFmTrack.fromJson({...value.toJson(), 'played_at': -1}),
        isNull,
      );
      expect(activityRecordExpiry({'version': 1, 'expires_at': 0}), isNull);
      expect(
        activityRecordExpiry({
          'version': 1,
          'expires_at': DateTime.now()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
        }),
        isNull,
      );
    },
  );

  for (final playing in [false, true]) {
    test(
      'recent footer publishes independently; game active=$playing',
      () async {
        final records = <Map<String, Object?>?>[];
        var visible = true;
        final source = Games()..playing = playing;
        final controller = ActivityController(
          userId: '@me:test',
          source: source,
          lastFm: Feed(),
          canShare: () => visible,
          canView: (_) => visible,
          read: (_) async => null,
          write: (_) async => fail('Must use the shared record serializer'),
          writeProfile: (record) async => records.add(record),
          upload: (_) async => Uri.parse('mxc://test/icon'),
        );
        addTearDown(controller.close);
        await controller.start();
        await controller.update(
          const ActivitySettings(
            detect: true,
            share: true,
            lastFmUser: 'user',
            lastFmKey: 'key',
            showLastFmRecent: true,
          ),
        );
        final record = records.last!;
        expect((record['lastfm_recent'] as Map)['album'], 'Album');
        expect(UserActivity.fromJson(record)?.name, playing ? 'Game' : null);
        expect(controller.lastFmRecentFor('@me:test')?.name, 'Track');
        await controller.update(
          controller.settings.copyWith(showLastFmRecent: false),
        );
        expect(records.last?['lastfm_recent'], isNull);
        expect(controller.lastFmRecentFor('@me:test'), isNull);
        expect(
          UserActivity.fromJson(records.last)?.name,
          playing ? 'Game' : null,
        );
        await controller.update(
          controller.settings.copyWith(showLastFmRecent: true),
        );
        visible = false;
        controller.visibilityChanged();
        expect(controller.lastFmRecentFor('@me:test'), isNull);
      },
    );
  }

  test(
    'receiver reads a recent-only record without inventing live activity',
    () async {
      var visible = true;
      final controller = ActivityController(
        userId: '@me:test',
        source: Games(),
        readStartDelay: Duration.zero,
        pollInterval: const Duration(milliseconds: 10),
        canShare: () => false,
        canView: (_) => visible,
        read: (_) async => {
          'version': 1,
          'expires_at': DateTime.now()
              .add(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
          'lastfm_recent': track().toJson(),
        },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
      );
      addTearDown(controller.close);
      await controller.start();
      controller.lastFmRecentFor('@peer:test');
      controller.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.lastFmRecentFor('@peer:test')?.album, 'Album');
      expect(controller.activityFor('@peer:test'), isNull);
      visible = false;
      controller.visibilityChanged();
      expect(controller.lastFmRecentFor('@peer:test'), isNull);
    },
  );

  testWidgets('compact footer wraps on mobile and disappears when cleared', (
    tester,
  ) async {
    final backend = ProfileBackend();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: ActivityScope(
          backend: backend,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.4),
                  ),
                  child: const LastFmRecentBar(userId: '@peer:test'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Last.fm · Last listened to'), findsOneWidget);
    expect(find.text('Track'), findsOneWidget);
    expect(find.text('Artist · Album'), findsOneWidget);
    expect(tester.takeException(), isNull);
    backend.recent = null;
    backend.notifyListeners();
    await tester.pump();
    expect(find.text('Track'), findsNothing);
  });
}
