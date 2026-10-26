import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/services/activity_controller.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_source.dart';
import 'package:deltiecord/services/activity_service_error.dart';
import 'package:deltiecord/models/user_activity.dart';

class _SlowSource extends DesktopActivitySource {
  final done = Completer<List<ActivityCandidate>>();
  @override
  bool get supported => true;
  @override
  Future<List<ActivityCandidate>> scan(ActivitySettings settings) =>
      done.future;
  @override
  Future<void> dispose() async {
    if (!done.isCompleted) done.complete([]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'cold profile history and live activity load while local detection is stalled',
    () async {
      final source = _SlowSource(), read = Completer<void>();
      final controller = ActivityController(
        userId: '@self:test',
        source: source,
        pollInterval: const Duration(milliseconds: 20),
        readStartDelay: Duration.zero,
        read: (id) async {
          if (!read.isCompleted) read.complete();
          return {
            'devices': {
              activityDeviceField('pc'): UserActivity(
                kind: ActivityKind.game,
                name: 'Game',
                expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              ).toJson(),
              lastFmHistoryField('pc'): {
                'version': 1,
                'track': LastFmTrack(
                  name: 'Song',
                  artist: 'Artist',
                  album: 'Album',
                  playedAt: DateTime.utc(2026, 10, 26),
                  url: Uri.parse('https://libre.fm/user/listener'),
                ).toJson(),
              },
            },
          };
        },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
        canShare: () => false,
      );
      addTearDown(controller.close);
      controller.watchUser('@friend:test', () => false);
      controller.watchHistory('@friend:test');
      final starting = controller.start();
      await read.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.lastFmRecentFor('@friend:test')!.name, 'Song');
      expect(controller.activitiesFor('@friend:test').live.single.name, 'Game');
      source.done.complete([]);
      await starting;
    },
  );
  test(
    'one failed profile does not put every other user on global backoff',
    () async {
      final source = _SlowSource()..done.complete([]);
      final fetched = Completer<void>();
      final controller = ActivityController(
        userId: '@self:test',
        source: source,
        readStartDelay: Duration.zero,
        read: (id) async {
          if (id == '@bad:test') {
            throw const ActivityServiceError('M_FORBIDDEN');
          }
          if (!fetched.isCompleted) fetched.complete();
          return null;
        },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
        canShare: () => false,
      );
      addTearDown(controller.close);
      controller.watchHistory('@bad:test');
      controller.watchHistory('@good:test');
      await controller.start();
      await fetched.future.timeout(const Duration(seconds: 1));
    },
  );
}
