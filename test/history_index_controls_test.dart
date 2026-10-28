import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/history_index.dart';
import 'package:deltiecord/services/history_index_native.dart';
import 'package:deltiecord/ui/history_index_settings.dart';
import 'support/fake_backend.dart';

class MemoryIndexStore extends HistoryStore {
  MemoryIndexStore() : super('test');
  final rows = <String, Map<String, Object?>>{};
  bool text = false;
  String? scope;
  int budget = 100, warning = 0, used = 0, writes = 0;
  @override
  Future<void> open() async {}
  @override
  Future<void> close() async {}
  @override
  Future<String?> loadScope() async => scope;
  @override
  Future<void> setScope(String value, Set<String> allowedRooms) async {
    scope = value;
    rows.removeWhere((_, row) => !allowedRooms.contains(row['room']));
  }

  @override
  Future<Map<String, Object?>> settings() async => {
    'enabled': text,
    'limit': budget,
    'warning': warning,
    'prompted': true,
  };
  @override
  Future<void> configure(bool enabled, int limit) async {
    text = enabled;
    if (limit != budget) warning = 0;
    budget = limit;
  }

  @override
  Future<void> put(
    List<Map<String, Object?>> values,
    bool text,
    int limit,
  ) async {
    writes++;
    for (final row in values) {
      rows[row['id'] as String] = row;
    }
  }

  @override
  Future<Map<String, int>> stats() async => {
    'entries': rows.length,
    'bytes': used,
    'budgetBytes': used,
    'warning': warning,
  };
  @override
  Future<void> clear() async {
    rows.clear();
    used = 0;
    warning = 0;
  }

  @override
  Future<void> acknowledgeWarning() async {
    warning = 1;
  }
}

class _Backend extends FakeBackend {
  _Backend(this.index);
  final HistoryIndex index;
  bool failFirst = false;
  @override
  HistoryIndex get historyIndex => index;
  @override
  Future<HistoryIndex?> openHistoryIndex() async {
    if (failFirst) {
      failFirst = false;
      return null;
    }
    return index;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('default is 100 MiB and burst writes are coalesced', () async {
    final store = MemoryIndexStore(),
        index = HistoryIndex('test', store: MemoryIndexStore());
    await index.open();
    expect(index.limitMiB, 100);
    await index.close();
    final batch = HistoryIndex('test', store: store);
    await batch.open();
    await batch.configure(text: true);
    final writes = [
      for (var i = 0; i < 50; i++)
        batch.ingest([
          {'id': '$i', 'room': 'r', 'time': i, 'body': 'hello', 'kind': ''},
        ]),
    ];
    await Future.wait(writes);
    expect(store.writes, 1);
    expect(store.rows.length, 50);
    await batch.close();
  });
  test(
    'capacity warning is acknowledged once until clear or budget change',
    () async {
      final store = MemoryIndexStore()..used = 80 * 1048576;
      final index = HistoryIndex('test', store: store);
      await index.open();
      await index.configure(text: true);
      expect(index.warningPending, true);
      await index.acknowledgeCapacityWarning();
      await index.refreshStats();
      expect(index.warningPending, false);
      await index.clear();
      expect(index.warningPending, false);
      store.used = 81 * 1048576;
      await index.refreshStats();
      expect(index.warningPending, true);
      await index.close();
    },
  );
  testWidgets(
    'unavailable storage can be retried instead of a permanently disabled setting',
    (tester) async {
      final index = HistoryIndex('test', store: MemoryIndexStore());
      await index.open();
      final backend = _Backend(index)..failFirst = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HistoryIndexSettings(backend: backend)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
      await tester.tap(find.text('Retry opening search storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(index.enabled, true);
      await tester.pumpWidget(const SizedBox());
      await index.close();
    },
  );
  testWidgets(
    '80 percent popup explains oldest-first pruning without deleting messages',
    (tester) async {
      final store = MemoryIndexStore()..used = 80 * 1048576;
      final index = HistoryIndex('test', store: store);
      await index.open();
      await index.configure(text: true);
      final backend = _Backend(index);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryIndexWarningGate(
              backend: backend,
              child: const Text('Chat'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Search cache almost full'), findsOneWidget);
      expect(
        find.textContaining('Older search results will be cleared'),
        findsOneWidget,
      );
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      backend.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Search cache almost full'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await index.close();
    },
  );
}
