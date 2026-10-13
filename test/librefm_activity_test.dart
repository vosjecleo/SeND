import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_controller.dart';
import 'package:deltiecord/services/lastfm_activity.dart';
import 'package:deltiecord/ui/activity_settings.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'lastfm_resume_test.dart' show Client, Response;
import 'lastfm_recent_test.dart' show Games;
import 'support/fake_backend.dart';

Map<String, Object?> feed() => {
  'recenttracks': {
    'track': [
      {
        'name': 'Playing',
        'artist': {'#text': 'Artist'},
        '@attr': {'nowplaying': 'true'},
        'url': 'https://libre.fm/artist/Artist/album/Album/track/Playing',
      },
      {
        'name': 'Completed',
        'artist': {'#text': 'Artist'},
        'album': {'#text': 'Album'},
        'date': {'uts': '1700000000'},
        'url': 'https://libre.fm/artist/Artist/album/Album/track/Completed',
      },
    ],
  },
};

class LibreFeed extends LastFmActivitySource {
  bool available = true;
  int reads = 0;
  @override
  Future<ActivityCandidate?> scan(ActivitySettings settings) async {
    reads++;
    recent = available
        ? lastFmRecentlyPlayed(feed(), settings.libreFmUser, libreFm: true)
        : null;
    return available
        ? lastFmNowPlaying(feed(), settings.libreFmUser, libreFm: true)
        : null;
  }
}

class CapturingClient extends Client {
  CapturingClient(this.capture) : super(Response('max-age=60', 200), () {});
  final void Function(Uri) capture;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    capture(url);
    return super.getUrl(url);
  }
}

class Backend extends FakeBackend {
  ActivitySettings settings = const ActivitySettings();
  @override
  ActivitySettings get activitySettings => settings;
  @override
  Future<void> updateActivitySettings(ActivitySettings value) async {
    settings = value;
    notifyListeners();
  }

  @override
  LastFmTrack? lastFmRecentFor(String id) =>
      lastFmRecentlyPlayed(feed(), 'user', libreFm: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('old preferences retain Last.fm; Libre.fm preferences round trip', () {
    final old = ActivitySettings.fromJson({
      'lastfm_user': 'old',
      'lastfm_key': 'key',
    });
    expect(old.useLibreFm, isFalse);
    expect(old.listeningUser, 'old');
    final linked = old.copyWith(libreFmUser: 'new', useLibreFm: true);
    final restored = ActivitySettings.fromJson(linked.toJson());
    expect(restored.listeningUser, 'new');
    expect(restored.lastFmKey, 'key');
    expect(restored.listeningProviderName, 'Libre.fm');
  });

  test(
    'public read uses Libre.fm only, without a key or password, and caches',
    () async {
      final requests = <Uri>[];
      final source = LastFmActivitySource(
        libreFm: true,
        clientFactory: () => CapturingClient(requests.add),
      );
      const settings = ActivitySettings(
        libreFmUser: 'test user',
        lastFmKey: 'never-send',
      );
      final live = await source.scan(settings);
      await source.scan(settings);
      expect(requests, hasLength(1));
      expect(requests.single.host, 'libre.fm');
      expect(requests.single.queryParameters['user'], 'test user');
      expect(requests.single.queryParameters.containsKey('api_key'), isFalse);
      expect(live?.id, 'librefm');
      expect(live?.lastFmUrl?.host, 'libre.fm');
      expect(source.recent?.name, 'Completed');
      expect(live?.playback, isNull);
      expect(live?.lastFmArtwork, isNull);
    },
  );

  test('links remain allowlisted; Libre.fm cannot supply Last.fm artwork', () {
    for (final url in [
      'https://libre.fm.evil.test/user/a',
      'http://libre.fm/user/a',
      'https://user@libre.fm/user/a',
      'https://libre.fm:444/user/a',
      'https://libre.fm/user/a?redirect=https://evil.test',
      'file:///user/a',
    ]) {
      expect(validListeningUrl(url), isNull);
    }
    final track = lastFmRecentlyPlayed(feed(), 'user', libreFm: true)!;
    expect(LastFmTrack.fromJson(track.toJson())?.url.host, 'libre.fm');
    expect(validLastFmUrl(track.url.toString()), isNull);
    expect(
      LastFmTrack.fromJson({
        ...track.toJson(),
        'artwork': 'https://lastfm.freetls.fastly.net/i/u/cover.jpg',
      })?.artwork,
      isNull,
    );
  });

  test(
    'Libre.fm publishes without Last.fm approval; offline preserves only history',
    () async {
      var online = true;
      final source = LibreFeed();
      final records = <String, Object?>{};
      final controller = ActivityController(
        userId: '@me:test',
        deviceId: 'test',
        source: Games(),
        libreFm: source,
        publicLastFmApproved: false,
        pollInterval: const Duration(days: 1),
        canShare: () => online,
        canView: (_) => online,
        read: (_) async => null,
        write: (_) async {},
        writeProfile: (value) async =>
            records[activityDeviceField('test')] = value,
        writeHistory: (value) async =>
            records[lastFmHistoryField('test')] = value,
        upload: (_) async => Uri.parse('mxc://test/icon'),
      );
      addTearDown(controller.close);
      await controller.start();
      await controller.update(
        const ActivitySettings(
          share: true,
          libreFmUser: 'user',
          useLibreFm: true,
          showLastFmRecent: true,
        ),
      );
      final live = UserActivities.fromRecords(records);
      expect(live.music?.lastFmUrl?.host, 'libre.fm');
      expect(live.recent?.name, 'Completed');
      final music =
          ((records[activityDeviceField('test')] as Map)['slots']
                  as Map)['music']
              as Map;
      expect(music['listening_url'], isNotNull);
      expect(music['lastfm_url'], isNull);
      online = false;
      await controller.update(controller.settings);
      expect(controller.activitiesFor('@me:test').live, isEmpty);
      expect(controller.lastFmRecentFor('@me:test')?.name, 'Completed');
      expect(source.reads, 1);
      online = true;
      source.available = false;
      await controller.update(
        controller.settings.copyWith(libreFmUser: 'different'),
      );
      expect(controller.lastFmRecentFor('@me:test'), isNull);
      expect(records[lastFmHistoryField('test')], isNull);
      await controller.update(controller.settings.copyWith(share: false));
      expect(controller.activitiesFor('@me:test').live, isEmpty);
    },
  );

  testWidgets('username linking selects Libre.fm without enabling sharing', (
    tester,
  ) async {
    final backend = Backend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActivitySettingsPanel(backend: backend),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Link Libre.fm'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'listener');
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    expect(backend.settings.libreFmUser, 'listener');
    expect(backend.settings.useLibreFm, isTrue);
    expect(backend.settings.share, isFalse);
    expect(
      find.text('Show Libre.fm last listened track on my profile'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer labels Libre.fm correctly on a narrow profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: ActivityScope(
          backend: Backend(),
          child: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: LastFmRecentBar(userId: '@me:test'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Libre.fm · Last listened to'), findsOneWidget);
    expect(find.textContaining('AudioScrobbler'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
