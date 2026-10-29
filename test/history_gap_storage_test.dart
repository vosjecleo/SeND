import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:deltiecord/services/history_index_native.dart';

void main() {
  test(
    'gap checkpoints are account-local and independent from manual download state',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final store = HistoryStore('gap-test', database: db);
      await store.open();
      await store.loadScope();
      await store.configure(true, 100);
      await store.saveDownloadState({'manual': true});
      await store.saveDownloadState({'gap': true}, slot: 2);
      await store.saveDownloadState(null);
      expect(await store.loadDownloadState(), null);
      expect(await store.loadDownloadState(slot: 2), {'gap': true});
      await store.saveDownloadState({'manual': true});
      await store.setScope('dms', {});
      expect(await store.loadDownloadState(), null);
      expect(await store.loadDownloadState(slot: 2), null);
      await store.saveDownloadState({'gap': true}, slot: 2);
      await store.configure(false, 100);
      expect(await store.loadDownloadState(slot: 2), null);
      await store.saveDownloadState({'gap': true}, slot: 2);
      await store.clear();
      expect(await store.loadDownloadState(slot: 2), null);
      await store.close();
    },
  );
}
