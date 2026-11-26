import 'dart:async';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/activity_controller.dart';
import 'package:deltiecord/services/activity_source.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _Source extends DesktopActivitySource {
  @override
  bool get supported => false;
  @override
  Future<void> dispose() async {}
}

class _Backend extends FakeBackend {
  final watching = <String, bool Function()>{};
  final exposed = <String>[];
  @override
  void refreshVisibleActivity(String userId) => exposed.add(userId);
  @override
  VoidCallback watchActivity(String id, {required bool Function() isVisible}) {
    watching[id] = isVisible;
    return () => watching.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'returning to a visible contact refreshes its existing activity sample',
    () async {
      var visible = true, reads = 0;
      final fresh = Completer<void>();
      final controller = ActivityController(
        userId: '@self:test',
        source: _Source(),
        read: (_) async {
          if (++reads == 2) fresh.complete();
          return {
            'devices': {
              mobilePresenceField('phone'): {
                'mobile': true,
                'version': 1,
                'expires_at': DateTime.now()
                    .add(const Duration(minutes: 2))
                    .millisecondsSinceEpoch,
              },
            },
          };
        },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
        canShare: () => false,
        pollInterval: const Duration(milliseconds: 15),
        readInterval: const Duration(days: 1),
        visibleReadInterval: const Duration(days: 1),
        exposureFreshness: Duration.zero,
      );
      addTearDown(controller.close);
      controller.watchUser('@peer:test', () => visible);
      await controller.start();
      expect(reads, 1);
      visible = false;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(reads, 1);
      visible = true;
      await fresh.future.timeout(const Duration(seconds: 2));
      expect(reads, 2);
    },
  );

  test(
    'watched activity refreshes sooner without polling hidden contacts',
    () async {
      final reads = <String, int>{};
      final refreshed = Completer<void>();
      final controller = ActivityController(
        userId: '@self:test',
        source: _Source(),
        read: (id) async {
          reads.update(id, (n) => n + 1, ifAbsent: () => 1);
          if (id == '@shown:test' && reads[id] == 2) refreshed.complete();
          return {
            'devices': {
              mobilePresenceField('phone'): {
                'version': 1,
                'mobile': true,
                'expires_at': DateTime.now()
                    .add(const Duration(minutes: 2))
                    .millisecondsSinceEpoch,
              },
            },
          };
        },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
        canShare: () => false,
        readInterval: const Duration(days: 1),
        visibleReadInterval: const Duration(milliseconds: 40),
        pollInterval: const Duration(milliseconds: 15),
      );
      addTearDown(controller.close);
      controller.watchUser('@shown:test', () => true);
      controller.watchUser('@hidden:test', () => false);
      await controller.start();
      await refreshed.future.timeout(const Duration(seconds: 2));
      expect(reads, {'@shown:test': 2});
    },
  );

  test(
    'visible phone gets one early lookup when its device field arrives late',
    () async {
      var reads = 0;
      final arrived = Completer<void>();
      final controller = ActivityController(
        userId: '@self:test',
        source: _Source(),
        read: (_) async => ++reads == 1
            ? null
            : {
                'devices': {
                  mobilePresenceField('phone'): {
                    'version': 1,
                    'mobile': true,
                    'expires_at': DateTime.now()
                        .add(const Duration(minutes: 2))
                        .millisecondsSinceEpoch,
                  },
                },
              },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
        canShare: () => false,
        pollInterval: const Duration(milliseconds: 100),
      );
      addTearDown(controller.close);
      controller.watchUser(
        '@phone:test',
        () => false,
      ); // The Home row is hidden.
      controller.watchUser(
        '@phone:test',
        () => true,
      ); // The chat header is visible.
      controller.addListener(() {
        if (!arrived.isCompleted &&
            controller.activitiesFor('@phone:test').mobileOnline) {
          arrived.complete();
        }
      });
      await controller.start();
      expect(reads, 1);
      expect(controller.activitiesFor('@phone:test').mobileOnline, isFalse);
      await arrived.future.timeout(const Duration(seconds: 8));
      expect(reads, 2);
    },
  );

  testWidgets('timeline header watches activity without opening a profile', (
    tester,
  ) async {
    final backend = _Backend();
    addTearDown(backend.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineActivityStatus(
            backend: backend,
            userId: '@phone:test',
            presence: UserPresence.online,
            fallback: const Text('Online'),
          ),
        ),
      ),
    );
    expect(backend.watching['@phone:test']!(), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(backend.watching, isEmpty);
  });

  test(
    'visible online users keep polling with no activity or profile clicks',
    () async {
      var visible = true;
      final readTwice = Completer<void>();
      final reads = <String>[];
      final controller = ActivityController(
        userId: '@self:test',
        source: _Source(),
        read: (id) async {
          reads.add(id);
          if (reads.length == 2) readTwice.complete();
          return null;
        },
        write: (_) async {},
        upload: (_) async => Uri.parse('mxc://test/icon'),
        canShare: () => false,
        canView: (id) => id != '@offline:test',
        readStartDelay: Duration.zero,
        readInterval: Duration.zero,
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(controller.close);
      final stop = controller.watchUser('@online:test', () => visible);
      controller.watchUser('@offline:test', () => true);
      await controller.start();
      await readTwice.future.timeout(const Duration(seconds: 4));
      visible = false;
      await Future<void>.delayed(const Duration(milliseconds: 1150));
      expect(reads, ['@online:test', '@online:test']);
      stop();
      visible = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(reads.length, 2);
    },
  );

  testWidgets(
    'row interest follows viewport bounds, offline state and disposal',
    (tester) async {
      final backend = _Backend();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      Widget row(String id, UserPresence presence) => ActivityWatch(
        backend: backend,
        userId: id,
        presence: presence,
        child: SizedBox(height: 60, child: Text(id)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 120,
                child: ListView(
                  controller: scroll,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
                  children: [
                    row('@first:test', UserPresence.online),
                    const SizedBox(height: 400),
                    row('@last:test', UserPresence.away),
                    row('@offline:test', UserPresence.offline),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(backend.watching['@first:test']!(), isTrue);
      expect(backend.exposed, contains('@first:test'));
      expect(backend.watching['@last:test']!(), isFalse);
      expect(backend.watching, isNot(contains('@offline:test')));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(backend.watching['@first:test']!(), isFalse);
      expect(backend.watching['@last:test']!(), isTrue);
      expect(backend.exposed, contains('@last:test'));
      await tester.pumpWidget(const SizedBox());
      expect(backend.watching, isEmpty);
    },
  );
}
