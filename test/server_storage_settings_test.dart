import 'package:deltiecord/ui/server_storage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _StorageBackend extends FakeBackend {
  _StorageBackend({this.quota = 12 * 1024 * 1024 * 1024});
  final int quota;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> serverStorage(
    String action, [
    Map<String, Object?>? body,
  ]) async {
    calls.add(action);
    return switch (action) {
      'usage' => {
        'used_bytes': 1048576,
        'quota_bytes': quota,
        'remaining_bytes': quota - 1048576,
        'categories': {
          'videos': {'bytes': 1048576, 'files': 1},
        },
      },
      'prune-preview' => {
        'files': [
          {'media_id': 'synthetic'},
        ],
        'bytes': 1048576,
        'token': 'synthetic-ticket-not-a-real-capability',
      },
      'prune' => {'deleted': 1},
      _ => throw StateError('Unexpected action'),
    };
  }
}

void main() {
  testWidgets(
    'desktop category hover highlights one segment and follows the cursor',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServerStorageSettings(
                backend: _StorageBackend(quota: 4 * 1048576),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final segment = find.byKey(const ValueKey('storage-segment-videos'));
      final fill = find.byKey(const ValueKey('storage-segment-fill-videos'));
      final available = find.byKey(
        const ValueKey('storage-segment-fill-available'),
      );
      Color? color(Finder finder) =>
          (tester.widget<DecoratedBox>(finder).decoration as BoxDecoration)
              .color;
      final original = color(fill), other = color(available);
      expect(find.widgetWithText(ListTile, 'Images'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      final cursor = tester.getCenter(segment);
      await mouse.moveTo(cursor);
      await tester.pumpAndSettle();
      expect(find.text('Videos: 1.0 MiB'), findsOneWidget);
      expect(find.textContaining('Images:'), findsNothing);
      expect(color(fill), isNot(original));
      expect(color(available), other);
      final label = find.byKey(const ValueKey('storage-category-tooltip'));
      final first = tester.getTopLeft(label);
      expect(first.dx, greaterThan(cursor.dx));
      await mouse.moveTo(cursor + const Offset(20, 0));
      await tester.pump();
      expect(tester.getTopLeft(label).dx - first.dx, closeTo(20, .1));
      await mouse.moveTo(const Offset(1190, 1190));
      await tester.pumpAndSettle();
      expect(label, findsNothing);
      expect(color(fill), original);
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
  testWidgets(
    'mobile storage graph fits and deletion always waits for confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = _StorageBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ServerStorageSettings(backend: backend),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Videos'), findsWidgets);
      final button = find.text('Preview files to delete');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Delete 1 uploads?'), findsOneWidget);
      expect(backend.calls, ['usage', 'prune-preview']);
      expect(find.textContaining("can't be undone"), findsOneWidget);
      expect(find.textContaining('Legacy uploads have'), findsNothing);
      expect(find.textContaining('storage-module update'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.calls.contains('prune'), false);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete uploads'));
      await tester.pumpAndSettle();
      expect(backend.calls.where((c) => c == 'prune').length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
