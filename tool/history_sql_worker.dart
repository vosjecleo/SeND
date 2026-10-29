// Runs in a dedicated worker. Only encrypted SQLite pages reach IndexedDB.
import 'dart:js_interop';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart'
    hide sqfliteFfiWebLoadSqlite3Wasm;
// Pinned sqflite web adapter: select the encryption VFS explicitly. Its default
// opener selects the underlying plaintext VFS even with sqlite3mc.wasm loaded.
// ignore: implementation_imports
import 'package:sqflite_common_ffi_web/src/import.dart';
// ignore: implementation_imports
import 'package:sqflite_common_ffi_web/src/sqflite_ffi_impl_web.dart';
// ignore: implementation_imports
import 'package:sqflite_common_ffi_web/src/web/load_sqlite_web.dart';
// ignore: implementation_imports
import 'package:sqflite_common_ffi_web/src/database_factory_web.dart';
import 'package:sqlite3/wasm.dart';
import 'package:deltiecord/services/history_index_sql.dart';

@JS('sendHistorySqlKey')
external JSPromise<JSString> _key(JSString account, JSBoolean existing);
@JS('sendHistorySqlRun')
external set _run(JSFunction value);
@JS('sendHistorySqlStage')
external set _stage(JSString value);

final _factoryReady = _createFactory();
Future<DatabaseFactory> _createFactory() async {
  final context = await sqfliteFfiWebLoadSqlite3Wasm(
    SqfliteFfiWebOptions(
      sqlite3WasmUri: Uri.parse('sqlite3mc.wasm'),
      indexedDbName: 'send-history-encrypted-v1',
    ),
  );
  sqfliteFfiHandler = _EncryptedHandler(context);
  return buildDatabaseFactory(
    tag: 'send-encrypted-web',
    invokeMethod: (method, [args]) =>
        ffiMethodCallHandleNoWebWorker(FfiMethodCall(method, args), context),
  );
}

class _EncryptedHandler extends SqfliteFfiHandlerWeb {
  _EncryptedHandler(super.context);
  @override
  Future<CommonDatabase> openPlatform(Map args) async =>
      context.wasmSqlite3!.open(
        args['path'] as String,
        vfs: 'multipleciphers-${context.fs!.name}',
        mode: args['readOnly'] == true
            ? OpenMode.readOnly
            : OpenMode.readWriteCreate,
      );
}

final _stores = <String, HistorySqlStore>{};

Future<HistorySqlStore> _store(String account) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(account)) {
    throw ArgumentError('Invalid account');
  }
  if (_stores[account] case final store?) return store;
  final filename = '$account.db';
  final factory = await _factoryReady;
  _stage = 'exists'.toJS;
  final exists = await factory.databaseExists(filename);
  _stage = 'key'.toJS;
  final password = (await _key(account.toJS, exists.toJS).toDart).toDart;
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(password)) {
    throw StateError('Invalid protected search key');
  }
  _stage = 'open'.toJS;
  final db = await factory.openDatabase(
    filename,
    options: OpenDatabaseOptions(
      onConfigure: (db) async {
        // Verify SQLite3MultipleCiphers before accepting
        // a key: ordinary SQLite silently ignores unknown encryption pragmas.
        _stage = 'cipher'.toJS;
        final cipher = await db.rawQuery('PRAGMA cipher');
        if (cipher.isEmpty) throw StateError('Encrypted SQLite unavailable');
        _stage = 'select-cipher'.toJS;
        // The pinned WASM build includes authenticated ChaCha20 encryption.
        await db.rawQuery("PRAGMA cipher='chacha20'");
        _stage = 'unlock'.toJS;
        await db.rawQuery("PRAGMA key='$password'");
        _stage = 'temp'.toJS;
        await db.execute('PRAGMA temp_store=MEMORY');
        _stage = 'verify'.toJS;
        await db.rawQuery('SELECT count(*) FROM sqlite_master');
      },
    ),
  );
  final store = HistorySqlStore(account, database: db);
  _stage = 'schema'.toJS;
  await store.open();
  _stores[account] = store;
  return store;
}

Future<Object?> _dispatch(String account, String operation, Map args) async {
  final store = await _store(account);
  final slot = args['slot'] == 2 ? 2 : 1;
  switch (operation) {
    case 'open':
      return true;
    case 'close':
      await store.close();
      _stores.remove(account);
      return true;
    case 'settings':
      return store.settings();
    case 'scope':
      return store.loadScope();
    case 'setScope':
      await store.loadScope();
      await store.setScope(
        args['scope'] as String,
        (args['rooms'] as List).cast<String>().toSet(),
      );
      return true;
    case 'downloadState':
      return store.loadDownloadState(slot: slot);
    case 'saveDownloadState':
      await store.saveDownloadState(
        args['state'] == null
            ? null
            : Map<String, Object?>.from(args['state'] as Map),
        slot: slot,
      );
      return true;
    case 'rows':
      return store.readRows((args['ids'] as List).cast<String>());
    case 'stats':
      return store.stats();
    case 'ackWarning':
      await store.acknowledgeWarning();
      return true;
    case 'revision':
      return store.revision(args['id'] as String);
    case 'clear':
      await store.clear();
      return true;
    case 'configure':
      await store.configure(
        args['enabled'] == true,
        (args['limit'] as num).toInt(),
      );
      return true;
    case 'put':
      final rows = (args['rows'] as List)
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList();
      final limit = (args['limit'] as num).toInt();
      if (args['preserve'] == true) {
        return store.putArchive(rows, args['text'] == true, limit);
      }
      await store.put(rows, args['text'] == true, limit);
      return true;
    case 'query':
      return store.query(
        args['room'] as String,
        terms: (args['terms'] as List? ?? []).cast<String>(),
        kind: args['kind'] as String?,
        sender: args['sender'] as String?,
        before: (args['before'] as num?)?.toInt(),
        after: (args['after'] as num?)?.toInt(),
        offset: (args['offset'] as num).toInt(),
        limit: (args['limit'] as num).toInt(),
      );
    case 'migrationBudget':
      await store.database!.rawQuery('PRAGMA max_page_count=524288');
      return true;
    case 'migrationSettings':
      await store.database!.insert('settings', {
        'id': 1,
        'enabled': args['enabled'] == true ? 1 : 0,
        'prompted': args['prompted'] == true ? 1 : 0,
        'budget': args['limit'] ?? 100,
        'warning_shown': args['warning'] ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await store.loadScope();
      if (args['scope'] != null) {
        await store.database!.insert('history_scope', {
          'id': 1,
          'scope': args['scope'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return true;
  }
  throw ArgumentError('Unknown search operation');
}

void main() {
  _run = ((JSString account, JSString op, JSAny? arguments) => _dispatch(
    account.toDart,
    op.toDart,
    (arguments?.dartify() as Map?) ?? {},
  ).then((value) => value.jsify()).toJS).toJS;
}
