import 'dart:async';
import 'package:deltiecord/models/chat_models.dart';
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
      expect(backend.watching['@last:test']!(), isFalse);
      expect(backend.watching, isNot(contains('@offline:test')));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(backend.watching['@first:test']!(), isFalse);
      expect(backend.watching['@last:test']!(), isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(backend.watching, isEmpty);
    },
  );
}
