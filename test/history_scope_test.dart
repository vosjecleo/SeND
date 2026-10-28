import 'package:deltiecord/services/history_scope.dart';
import 'package:deltiecord/services/history_index.dart';
import 'package:deltiecord/services/history_index_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'history scopes are cumulative, with legacy settings preserving all rooms',
    () {
      expect(HistoryScope.parse(null), HistoryScope.all);
      expect(HistoryScope.parse('unknown'), HistoryScope.all);
      expect(HistoryRoomKind.values.where(HistoryScope.dms.includes), [
        HistoryRoomKind.dm,
      ]);
      expect(HistoryRoomKind.values.where(HistoryScope.groups.includes), [
        HistoryRoomKind.dm,
        HistoryRoomKind.group,
      ]);
      expect(
        HistoryRoomKind.values.where(HistoryScope.all.includes),
        HistoryRoomKind.values,
      );
    },
  );
  test(
    'changing scope prunes excluded text and media references and preserves settings',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final index = HistoryIndex(
        'fixture',
        store: HistoryStore('fixture', database: db),
      );
      await index.open();
      addTearDown(index.close);
      await index.configure(text: true);
      await index.ingest([
        for (final room in ['dm', 'group', 'server'])
          {
            'id': '\$$room',
            'room': '!$room:test',
            'sender': '@a:test',
            'time': 1,
            'kind': 'image',
            'body': 'needle $room',
          },
      ]);
      await index.saveDownloadState({'saved': true});
      await index.setScope(HistoryScope.dms, {'!dm:test'});
      expect(index.scope, HistoryScope.dms);
      expect(await index.query('!dm:test', terms: ['needle']), ['\$dm']);
      expect(await index.query('!server:test'), isEmpty);
      expect(await index.query('!group:test'), isEmpty);
      expect(await index.loadDownloadState(), isNull);
      await index.configure(text: true, limit: 250);
      final store = HistoryStore('fixture', database: db);
      await store.open();
      expect(await store.loadScope(), 'dms');
      expect(index.enabled, true);
      expect(index.entries, 1);
      await index.ingest([
        {
          'id': '\$late',
          'room': '!server:test',
          'room_kind': 'server',
          'sender': '@a:test',
          'time': 2,
          'kind': '',
          'body': 'late server event',
        },
      ]);
      expect(await index.query('!server:test'), isEmpty);
      expect(index.entries, 1);
    },
  );
}
