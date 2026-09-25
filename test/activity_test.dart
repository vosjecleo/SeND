import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/activity_controller.dart';
import 'package:deltiecord/services/activity_source.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_service_error.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/navigation_polish.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'widget_test.dart' show FakeBackend;

class Source extends DesktopActivitySource {
  List<ActivityCandidate> values = [];
  bool fail = false;
  @override
  bool get supported => true;
  @override
  Future<List<ActivityCandidate>> scan(ActivitySettings settings) async {
    if (fail) throw ArgumentError('unsendable worker input');
    return settings.detect ? values : [];
  }

  @override
  Future<void> dispose() async {}
}

class Backend extends FakeBackend {
  UserActivity? activity;
  @override
  UserActivity? activityFor(String userId) => activity;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'periodic activity scan recovers and renews without toggling settings',
    () async {
      final source = Source()
        ..fail = true
        ..values = [
          const ActivityCandidate(
            id: 'game',
            name: 'Game',
            kind: ActivityKind.game,
          ),
        ];
      final writes = <UserActivity?>[];
      final controller = ActivityController(
        userId: '@test:example.org',
        source: source,
        pollInterval: const Duration(milliseconds: 20),
        heartbeat: const Duration(milliseconds: 60),
        read: (_) async => null,
        write: (v) async => writes.add(v),
        upload: (_) async => Uri.parse('mxc://example.org/icon'),
        canShare: () => true,
      );
      addTearDown(controller.close);
      await controller.start();
      await controller.update(
        const ActivitySettings(detect: true, share: true),
      );
      expect(controller.warning, contains('Local activity detection'));
      source.fail = false;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(writes.whereType<UserActivity>().length, greaterThanOrEqualTo(2));
      expect(controller.warning, isNull);
    },
  );

  test(
    'failed clearing respects retry-after instead of looping immediately',
    () async {
      final source = Source()
        ..values = [
          const ActivityCandidate(
            id: 'game',
            name: 'Game',
            kind: ActivityKind.game,
          ),
        ];
      var clears = 0;
      final controller = ActivityController(
        userId: '@test:example.org',
        source: source,
        pollInterval: const Duration(milliseconds: 20),
        read: (_) async => null,
        write: (v) async {
          if (v == null) {
            clears++;
            throw const ActivityServiceError(
              'M_LIMIT_EXCEEDED',
              retryAfter: Duration(milliseconds: 200),
            );
          }
        },
        upload: (_) async => Uri.parse('mxc://example.org/icon'),
        canShare: () => true,
      );
      addTearDown(controller.close);
      await controller.start();
      await controller.update(
        const ActivitySettings(detect: true, share: true),
      );
      await controller.update(
        const ActivitySettings(detect: true, share: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 65));
      expect(clears, 1);
      expect(controller.warning, contains('rate-limited'));
      expect(controller.activityFor('@test:example.org'), isNull);
    },
  );

  test(
    'Last.fm public sharing can be explicitly disabled if approval is revoked',
    () async {
      final source = Source()
        ..values = [
          ActivityCandidate(
            id: 'lastfm',
            name: 'Track',
            kind: ActivityKind.music,
            lastFmUrl: Uri.parse('https://www.last.fm/music/Artist/_/Track'),
          ),
        ];
      final writes = <UserActivity?>[];
      final controller = ActivityController(
        userId: '@test:example.org',
        source: source,
        publicLastFmApproved: false,
        read: (_) async => null,
        write: (v) async => writes.add(v),
        upload: (_) async => Uri.parse('mxc://example.org/icon'),
        canShare: () => true,
      );
      addTearDown(controller.close);
      await controller.start();
      await controller.update(
        const ActivitySettings(detect: true, share: true),
      );
      expect(writes, isEmpty);
      expect(controller.activityFor('@test:example.org')?.name, 'Track');
      expect(controller.warning, contains('local only'));
    },
  );

  test(
    'optional playback metadata validates bounds, clamps and round trips',
    () {
      final now = DateTime.now();
      final activity = UserActivity(
        kind: ActivityKind.music,
        name: 'Song',
        expiresAt: now.add(const Duration(minutes: 2)),
        playback: ActivityPlayback(
          positionMs: 42000,
          durationMs: 240000,
          sampledAt: now,
        ),
      );
      final decoded = UserActivity.fromJson(activity.toJson(), now: now)!;
      expect(
        decoded.playback!.positionAt(now.add(const Duration(seconds: 2))),
        44000,
      );
      expect(
        decoded.playback!.positionAt(now.add(const Duration(hours: 1))),
        240000,
      );
      expect(
        ActivityPlayback.fromJson({
          ...activity.playback!.toJson(),
          'duration_ms': 0,
        }, now: now),
        isNull,
      );
      expect(
        UserActivity.fromJson({
          ...activity.toJson(),
          'playback': {'bad': true},
        }, now: now)?.name,
        'Song',
      );
      expect(
        validLastFmUrl('https://www.last.fm.attacker.test/music/track'),
        isNull,
      );
      expect(
        validLastFmUrl('https://user:password@www.last.fm/music/track'),
        isNull,
      );
    },
  );

  testWidgets('music progress shows padded elapsed and total clocks', (
    tester,
  ) async {
    final activity = UserActivity(
      kind: ActivityKind.music,
      name: 'Song',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      playback: ActivityPlayback(
        positionMs: 42000,
        durationMs: 239830,
        sampledAt: DateTime.now(),
        playing: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(body: ActivityProgress(activity: activity)),
      ),
    );
    expect(find.text('00:00:42'), findsOneWidget);
    expect(find.text('00:03:59'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(42000 / 239830, .001),
    );
    expect(activityClock(3661000), '01:01:01');
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'activity viewing defers startup requests and backs off on read errors',
    () async {
      var reads = 0;
      final controller = ActivityController(
        userId: '@test:example.org',
        source: Source(),
        read: (_) async {
          reads++;
          throw StateError('rate limited');
        },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://example.org/icon'),
        canShare: () => false,
      );
      await controller.start();
      controller.activityFor('@other:example.org');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(reads, 0);
      await Future<void>.delayed(const Duration(seconds: 16));
      expect(reads, 1);
      controller.activityFor('@second:example.org');
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(reads, 1);
      await controller.close();
    },
  );
  test('opting out during icon upload cannot publish afterwards', () async {
    final source = Source()
      ..values = [
        ActivityCandidate(
          id: 'game',
          name: 'Game',
          kind: ActivityKind.game,
          iconBytes: Uint8List.fromList([1]),
        ),
      ];
    final entered = Completer<void>();
    final uploaded = Completer<Uri>();
    final writes = <UserActivity?>[];
    final controller = ActivityController(
      userId: '@test:example.org',
      source: source,
      read: (_) async => null,
      write: (value) async => writes.add(value),
      upload: (_) {
        entered.complete();
        return uploaded.future;
      },
      canShare: () => true,
    );
    await controller.start();
    final enabling = controller.update(
      const ActivitySettings(detect: true, share: true),
    );
    await entered.future;
    final disabling = controller.update(
      const ActivitySettings(detect: true, share: false),
    );
    uploaded.complete(Uri.parse('mxc://example.org/icon'));
    await Future.wait([enabling, disabling]);
    expect(writes, isEmpty);
    await controller.close();
  });
  test(
    'public activity is bounded, expires, and never contains detection rules',
    () {
      final now = DateTime(2026, 9, 25);
      final activity = UserActivity(
        kind: ActivityKind.game,
        name: 'Game',
        expiresAt: now.add(const Duration(minutes: 2)),
        icon: Uri.parse('mxc://example.org/icon'),
      );
      expect(UserActivity.fromJson(activity.toJson(), now: now)?.name, 'Game');
      expect(
        UserActivity.fromJson(
          activity.toJson(),
          now: now.add(const Duration(minutes: 3)),
        ),
        isNull,
      );
      expect(
        UserActivity.fromJson({
          ...activity.toJson(),
          'expires_at': now.add(const Duration(days: 1)).millisecondsSinceEpoch,
        }, now: now),
        isNull,
      );
      expect(
        UserActivity.fromJson({
          ...activity.toJson(),
          'icon': 'https://tracker.example/icon',
        }, now: now)?.icon,
        isNull,
      );
      expect(
        UserActivity.fromJson({
          ...activity.toJson(),
          'kind': 'unknown',
        }, now: now),
        isNull,
      );
      expect(activity.toJson().keys, isNot(contains('rules')));
    },
  );
  test(
    'detect and share are opt-in; unknown programs require classification',
    () async {
      final source = Source()
        ..values = [
          const ActivityCandidate(id: '/private/user/tool', name: 'Tool'),
        ];
      final writes = <UserActivity?>[];
      var visible = true;
      final controller = ActivityController(
        userId: '@test:example.org',
        source: source,
        read: (_) async => null,
        write: (value) async => writes.add(value),
        upload: (_) async => Uri.parse('mxc://example.org/icon'),
        canShare: () => visible,
      );
      await controller.start();
      expect(writes, isEmpty);
      await controller.update(
        const ActivitySettings(detect: true, share: true),
      );
      expect(writes, isEmpty);
      await controller.update(
        controller.settings.copyWith(
          rules: {
            '/private/user/tool': const ActivityRule(
              name: 'My game',
              kind: ActivityKind.game,
            ),
          },
        ),
      );
      expect(writes.single!.name, 'My game');
      expect(writes.single!.toJson().toString(), isNot(contains('/private')));
      visible = false;
      await controller.update(controller.settings);
      expect(writes.last, isNull);
      visible = true;
      await controller.update(controller.settings.copyWith(share: false));
      expect(writes.whereType<UserActivity>(), hasLength(1));
      await controller.close(clear: true);
    },
  );
  test(
    'logout waits for an in-flight publication and clears it last',
    () async {
      final source = Source()
        ..values = [
          const ActivityCandidate(
            id: 'game',
            name: 'Game',
            kind: ActivityKind.game,
          ),
        ];
      final entered = Completer<void>();
      final release = Completer<void>();
      final writes = <UserActivity?>[];
      final controller = ActivityController(
        userId: '@test:example.org',
        source: source,
        read: (_) async => null,
        write: (value) async {
          if (value != null) {
            entered.complete();
            await release.future;
          }
          writes.add(value);
        },
        upload: (_) async => Uri.parse('mxc://example.org/icon'),
        canShare: () => true,
      );
      await controller.start();
      final updating = controller.update(
        const ActivitySettings(detect: true, share: true),
      );
      await entered.future;
      final closing = controller.close(clear: true);
      release.complete();
      await Future.wait([updating, closing]);
      expect(writes, hasLength(2));
      expect(writes.last, isNull);
    },
  );
  testWidgets('online activities get an icon; offline statuses are hidden', (
    tester,
  ) async {
    final backend = Backend()
      ..activity = UserActivity(
        kind: ActivityKind.music,
        name: 'Song',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
    Widget view(UserPresence presence) => MaterialApp(
      theme: ThemeData(
        extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
      ),
      home: Scaffold(
        body: ActivityStatus(
          backend: backend,
          userId: '@test:example.org',
          presence: presence,
          status: 'Status',
        ),
      ),
    );
    await tester.pumpWidget(view(UserPresence.online));
    expect(find.text('Listening to Song'), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
    await tester.pumpWidget(view(UserPresence.offline));
    expect(find.text('Listening to Song'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  });
  test('a configured but inactive program never publishes', () async {
    final source = Source()
      ..values = [
        const ActivityCandidate(
          id: 'inactive',
          name: 'Inactive game',
          kind: ActivityKind.game,
          running: false,
        ),
      ];
    final writes = <UserActivity?>[];
    final controller = ActivityController(
      userId: '@test:example.org',
      source: source,
      read: (_) async => null,
      write: (value) async => writes.add(value),
      upload: (_) async => Uri.parse('mxc://example.org/icon'),
      canShare: () => true,
    );
    await controller.start();
    await controller.update(
      const ActivitySettings(
        detect: true,
        share: true,
        rules: {
          'inactive': ActivityRule(
            name: 'Inactive game',
            kind: ActivityKind.game,
          ),
        },
      ),
    );
    expect(writes.whereType<UserActivity>(), isEmpty);
    await controller.close();
  });

  testWidgets(
    'profile activity separates heading and title; roles use quiet badges',
    (tester) async {
      final backend = Backend()
        ..activity = UserActivity(
          kind: ActivityKind.game,
          name: 'Game title',
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        );
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
                  ActivityBlock(userId: '@test:example.org'),
                  MemberRoleBadge(powerLevel: 100),
                  MemberRoleBadge(powerLevel: 50),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Currently playing:'), findsOneWidget);
      expect(find.text('Game title'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Mod'), findsOneWidget);
      expect(find.byType(Badge), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      backend.dispose();
    },
  );
}
