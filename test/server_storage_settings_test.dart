import 'package:deltiecord/ui/server_storage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _StorageBackend extends FakeBackend {
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
        'quota_bytes': 12 * 1024 * 1024 * 1024,
        'remaining_bytes': 12 * 1024 * 1024 * 1024 - 1048576,
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
      expect(find.textContaining('cannot be undone'), findsOneWidget);
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
