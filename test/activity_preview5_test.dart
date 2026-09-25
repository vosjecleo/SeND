import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_controller.dart';
import 'package:deltiecord/services/activity_source.dart';
import 'package:deltiecord/services/lastfm_activity.dart';
import 'package:deltiecord/ui/activity_settings.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/media_album.dart';
import 'widget_test.dart' show FakeBackend;

class NoDesktop extends DesktopActivitySource {
  @override
  bool get supported => false;
  @override
  Future<void> dispose() async {}
}

class MusicFeed extends LastFmActivitySource {
  int reads = 0;
  @override
  Future<ActivityCandidate?> scan(ActivitySettings settings) async {
    reads++;
    return ActivityCandidate(
      id: 'lastfm',
      name: 'Song',
      kind: ActivityKind.music,
      lastFmUrl: Uri.parse('https://www.last.fm/music/Artist/_/Song'),
    );
  }
}

class PreviewBackend extends FakeBackend {
  final idleReports = <bool>[];
  UserActivity? activity;
  @override
  UserActivity? activityFor(String id) => activity;
  @override
  Future<Uint8List?> loadActivityIcon(Uri uri) => downloadAttachment('art');
  @override
  void setDesktopIdle(bool idle) => idleReports.add(idle);
  @override
  Future<Uint8List> downloadAttachment(
    String id, {
    bool thumbnail = false,
  }) async =>
      Uint8List.fromList(img.encodePng(img.Image(width: 160, height: 90)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Last.fm works without desktop detection and stops in background',
    () async {
      var foreground = true;
      final feed = MusicFeed();
      final writes = <UserActivity?>[];
      final controller = ActivityController(
        userId: '@me:test',
        source: NoDesktop(),
        lastFm: feed,
        isForeground: () => foreground,
        canShare: () => foreground,
        canView: (_) => foreground,
        read: (_) async => null,
        write: (v) async => writes.add(v),
        upload: (_) async => Uri.parse('mxc://test/icon'),
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(controller.close);
      await controller.start();
      await controller.update(
        const ActivitySettings(share: true, lastFmUser: 'me', lastFmKey: 'key'),
      );
      expect(controller.activityFor('@me:test')?.name, 'Song');
      expect(writes.whereType<UserActivity>().single.name, 'Song');
      foreground = false;
      controller.visibilityChanged();
      final reads = feed.reads;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(feed.reads, reads);
      expect(controller.activityFor('@me:test'), isNull);
      foreground = true;
      controller.visibilityChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.activityFor('@me:test')?.name, 'Song');
    },
  );

  test(
    'offline presence suppresses reads and drops in-flight responses',
    () async {
      var visible = false;
      var reads = 0;
      final response = Completer<Object?>();
      final controller = ActivityController(
        userId: '@me:test',
        source: NoDesktop(),
        readStartDelay: Duration.zero,
        canShare: () => false,
        canView: (_) => visible,
        read: (_) {
          reads++;
          return response.future;
        },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(controller.close);
      await controller.start();
      expect(controller.activityFor('@peer:test'), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reads, 0);
      visible = true;
      controller.activityFor('@peer:test');
      controller.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reads, 1);
      visible = false;
      controller.visibilityChanged();
      response.complete(
        UserActivity(
          kind: ActivityKind.game,
          name: 'Hidden',
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        ).toJson(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.activityFor('@peer:test'), isNull);
      visible = true;
      expect(controller.activityFor('@peer:test'), isNull);
    },
  );

  test('Last.fm ignores old scrobbles and never invents timing or artwork', () {
    final track = {
      'name': 'Song',
      'artist': {'#text': 'Artist'},
      '@attr': {'nowplaying': 'true'},
      'image': [
        {'#text': 'https://example.org/art'},
      ],
    };
    final value = lastFmNowPlaying({
      'recenttracks': {
        'track': [track],
      },
    }, 'me')!;
    expect(value.playback, isNull);
    expect(value.iconBytes, isNull);
    expect(
      lastFmNowPlaying({
        'recenttracks': {
          'track': [
            {...track, '@attr': {}},
          ],
        },
      }, 'me'),
      isNull,
    );
  });

  testWidgets('non-desktop settings expose Last.fm but not process detection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ActivitySettingsPanel(backend: FakeBackend())),
      ),
    );
    expect(find.text('Connect Last.fm'), findsOneWidget);
    expect(find.text('Add program'), findsNothing);
    expect(find.text('Detect games and music on this device'), findsNothing);
  });

  testWidgets('desktop activity reporter covers popup routes', (tester) async {
    final backend = PreviewBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.linux),
    );
    await tester.pump();
    final context = tester.element(find.byType(Navigator).first);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          content: TextButton(
            onPressed: () {},
            child: const Text('Popup interaction'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    backend.idleReports.clear();
    await tester.tap(find.text('Popup interaction'));
    expect(backend.idleReports, contains(false));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('album image fills its tile and opens original on tap', (
    tester,
  ) async {
    final backend = PreviewBackend();
    var opened = false;
    final message = ChatMessage(
      id: 'image',
      pending: false,
      sender: 'Me',
      body: '',
      timestamp: DateTime.now(),
      attachment: const ChatAttachment(
        kind: AttachmentKind.image,
        name: 'wide.png',
        mimeType: 'image/png',
        size: 100,
        encrypted: false,
        spoiler: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 430,
              child: MediaAlbumGrid(
                messages: [message, message],
                itemBuilder: (_, m) => MediaAlbumTile(
                  backend: backend,
                  message: m,
                  onOpen: () => opened = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = find.byType(Image).first;
    expect(tester.getSize(image), const Size(214, 280));
    expect(tester.widget<Image>(image).fit, BoxFit.cover);
    await tester.tap(image);
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('music cover has a square frame and never stretches', (
    tester,
  ) async {
    final backend = PreviewBackend()
      ..activity = UserActivity(
        kind: ActivityKind.music,
        name: 'Song',
        icon: Uri.parse('mxc://test/cover'),
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityScope(
          backend: backend,
          child: const Scaffold(
            body: SizedBox(
              width: 300,
              child: ActivityBlock(userId: '@me:test'),
            ),
          ),
        ),
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = find.byType(Image);
    expect(tester.getSize(image), const Size(64, 64));
    expect(tester.widget<Image>(image).fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });
}
