import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../matrix/encrypted_android_database.dart';
import 'private_file_store.dart';
import 'history_index_limits.dart';

bool get historyIndexEncryptedAtRest => Platform.isAndroid;

int _sqliteInteger(Object? value) {
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw StateError('Invalid numeric value from local search storage.');
}

class HistoryStore {
  HistoryStore(this.account, {this.database});
  final String account;
  Database? database;
  bool _fts = false;
  String openStage = 'directory';
  String failureCode(Object error) {
    if (error is DatabaseException) {
      return 'SQLITE_${error.getResultCode() ?? 0}';
    }
    if (error is FileSystemException) {
      return 'FILE_${error.osError?.errorCode ?? 0}';
    }
    if (error is StateError) {
      final code = RegExp(
        r'SQLITE_[0-9]+',
      ).firstMatch(error.message.toString());
      if (code != null) return code.group(0)!;
    }
    return error.runtimeType.toString();
  }

  Future<void> open() async {
    if (database == null) {
      final folder = Directory(
        '${(await getApplicationSupportDirectory()).path}/deltiecord/search',
      );
      await ensurePrivateDirectory(folder);
      final path = '${folder.path}/$account.db';
      openStage = 'database';
      if (Platform.isAndroid) {
        database = await openEncryptedAndroidDatabase(path);
      } else {
        sqfliteFfiInit();
        database = await databaseFactoryFfi.openDatabase(path);
      }
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['600', path]);
      }
    }
    final db = database!;
    openStage = 'schema';
    await db.execute(
      'CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY, enabled INTEGER, prompted INTEGER, budget INTEGER)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, room TEXT NOT NULL, time INTEGER NOT NULL, kind TEXT NOT NULL, sender TEXT NOT NULL, body TEXT NOT NULL, bytes INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS history_download (id INTEGER PRIMARY KEY, state TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS event_room_time ON events(room,time DESC,id)',
    );
    final columns = (await db.rawQuery(
      'PRAGMA table_info(events)',
    )).map((r) => r['name']).toSet();
    if (!columns.contains('revision')) {
      await db.execute('ALTER TABLE events ADD COLUMN revision TEXT');
    }
    if (!columns.contains('edited_at')) {
      await db.execute(
        'ALTER TABLE events ADD COLUMN edited_at INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS event_kind_time ON events(room,kind,time DESC,id)',
    );
    final settingsColumns = (await db.rawQuery(
      'PRAGMA table_info(settings)',
    )).map((r) => r['name']).toSet();
    if (!settingsColumns.contains('warning_shown')) {
      await db.execute(
        'ALTER TABLE settings ADD COLUMN warning_shown INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS history_totals (id INTEGER PRIMARY KEY, n INTEGER NOT NULL, size INTEGER NOT NULL)',
    );
    if ((await db.query('history_totals', columns: ['id'], limit: 1)).isEmpty) {
      await db.execute(
        'INSERT INTO history_totals SELECT 1,COUNT(*),COALESCE(SUM(bytes),0) FROM events',
      );
    }
    await db.execute(
      'CREATE TRIGGER IF NOT EXISTS history_added AFTER INSERT ON events BEGIN UPDATE history_totals SET n=n+1,size=size+new.bytes WHERE id=1; END',
    );
    await db.execute(
      'CREATE TRIGGER IF NOT EXISTS history_removed AFTER DELETE ON events BEGIN UPDATE history_totals SET n=n-1,size=size-old.bytes WHERE id=1; END',
    );
    await db.execute(
      'CREATE TRIGGER IF NOT EXISTS history_updated AFTER UPDATE ON events BEGIN UPDATE history_totals SET size=size-old.bytes+new.bytes WHERE id=1; END',
    );
    try {
      await db.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(id UNINDEXED, room UNINDEXED, body, tokenize='trigram')",
      );
      final version = _sqliteInteger(
        (await db.rawQuery('PRAGMA user_version')).first.values.first,
      );
      if (version < 1) {
        await db.transaction((txn) async {
          await txn.delete('search');
          await txn.execute(
            "INSERT INTO search(rowid,id,room,body) SELECT rowid,id,room,body FROM events WHERE body<>''",
          );
          await txn.execute('PRAGMA user_version=1');
        });
      }
      _fts = true;
    } catch (_) {
      _fts = false;
    }
    final config = await settings();
    openStage = 'page-limit';
    final limit = (config['limit'] as int? ?? 100).clamp(
      16,
      historyIndexMaxMiB,
    );
    final pages = _sqliteInteger(
      (await db.rawQuery('PRAGMA page_size')).first.values.first,
    );
    await db.rawQuery(
      'PRAGMA max_page_count = ${limit * 1024 * 1024 ~/ pages}',
    );
  }

  Future<Map<String, Object?>> settings() async {
    final rows = await database!.query('settings', limit: 1);
    if (rows.isEmpty) return {};
    return {
      'enabled': rows.first['enabled'] == 1,
      'prompted': rows.first['prompted'] == 1,
      'limit': rows.first['budget'],
      'warning': rows.first['warning_shown'],
    };
  }

  Future<String?> loadScope() async {
    await database!.execute(
      'CREATE TABLE IF NOT EXISTS history_scope (id INTEGER PRIMARY KEY, scope TEXT NOT NULL)',
    );
    final rows = await database!.query('history_scope', where: 'id=1');
    return rows.isEmpty ? null : rows.single['scope'] as String;
  }

  Future<void> setScope(String scope, Set<String> allowedRooms) async {
    final db = database!;
    await db.transaction((txn) async {
      await txn.insert('history_scope', {
        'id': 1,
        'scope': scope,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final rooms = await txn.rawQuery('SELECT DISTINCT room FROM events');
      for (final row in rooms) {
        final room = row['room'] as String;
        if (allowedRooms.contains(room)) continue;
        if (_fts) {
          await txn.rawDelete(
            'DELETE FROM search WHERE rowid IN (SELECT rowid FROM events WHERE room=?)',
            [room],
          );
        }
        await txn.delete('events', where: 'room=?', whereArgs: [room]);
      }
      await txn.delete('history_download');
      await txn.rawUpdate('UPDATE settings SET warning_shown=0 WHERE id=1');
    });
    await db.execute('VACUUM');
  }

  Future<void> configure(bool enabled, int limit) async {
    final db = database!;
    final previous = await settings();
    await db.insert('settings', {
      'id': 1,
      'enabled': enabled ? 1 : 0,
      'prompted': 1,
      'budget': limit,
      'warning_shown': previous['limit'] == limit
          ? previous['warning'] ?? 0
          : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (!enabled) {
      await saveDownloadState(null);
      await db.transaction((txn) async {
        await txn.delete('events', where: "kind = ''");
        await txn.rawUpdate(
          "UPDATE events SET bytes=256+length(id)+length(room)+length(sender),body='' ",
        );
        if (_fts) await txn.delete('search');
      });
    }
    await _trim(limit);
    await db.execute('VACUUM');
    final pages = _sqliteInteger(
      (await db.rawQuery('PRAGMA page_size')).first.values.first,
    );
    await db.rawQuery(
      'PRAGMA max_page_count = ${limit * 1024 * 1024 ~/ pages}',
    );
  }

  Future<void> put(List<Map<String, Object?>> rows, bool text, int limit) =>
      _put(rows, text, limit, evict: true);

  Future<bool> putArchive(
    List<Map<String, Object?>> rows,
    bool text,
    int limit,
  ) async {
    if (rows.isEmpty) return true;
    if (rows.length > 200) throw ArgumentError('History page is too large');
    final db = database!;
    final total = (await db.query('history_totals', where: 'id=1')).single;
    final ids = rows.map((r) => r['id'] as String).toSet().toList();
    final existing = await db.query(
      'events',
      columns: ['id', 'bytes', 'edited_at'],
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
    final oldById = {for (final row in existing) row['id']: row};
    final applicable = rows
        .where(
          (row) =>
              row['deleted'] == true ||
              (oldById[row['id']]?['edited_at'] as int? ?? 0) <=
                  (row['edited_at'] as int? ?? 0),
        )
        .toList();
    final changedIds = applicable.map((row) => row['id']).toSet();
    final replaced = existing
        .where((row) => changedIds.contains(row['id']))
        .toList();
    final oldBytes = replaced.fold<int>(
      0,
      (sum, row) => sum + (row['bytes'] as int),
    );
    final live = applicable.where(
      (r) =>
          r['deleted'] != true &&
          (text || (r['kind'] as String? ?? '').isNotEmpty),
    );
    final incoming = live.fold<int>(
      0,
      (sum, row) => sum + 1024 + utf8.encode(jsonEncode(row)).length * 3,
    );
    if ((total['size'] as int) - oldBytes + incoming > limit * 1048576 * .65 ||
        (total['n'] as int) -
                replaced.length +
                live.map((r) => r['id']).toSet().length >
            historyIndexEntryLimit(limit)) {
      return false;
    }
    try {
      await _put(rows, text, limit, evict: false);
      return true;
    } on DatabaseException catch (error) {
      if (((error.getResultCode() ?? 0) & 255) == 13 ||
          error.toString().toLowerCase().contains('database or disk is full')) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _put(
    List<Map<String, Object?>> rows,
    bool text,
    int limit, {
    required bool evict,
  }) async {
    final db = database!;
    if (rows.length > 32) {
      for (var i = 0; i < rows.length; i += 32) {
        await _put(rows.skip(i).take(32).toList(), text, limit, evict: evict);
      }
      return;
    }
    // Leave room for FTS segments, indexes and transaction bookkeeping rather
    // than waiting for SQLite's hard cap to abort a transaction mid-batch.
    final incoming = rows.fold<int>(
      0,
      (n, row) => n + 1024 + utf8.encode(jsonEncode(row)).length * 3,
    );
    final total = (await db.query('history_totals', where: 'id=1')).single;
    if ((total['size'] as int) + incoming >= limit * 1048576 * .65 * .8 ||
        (total['n'] as int) + rows.length >=
            historyIndexEntryLimit(limit) * .8) {
      await db.rawUpdate(
        'UPDATE settings SET warning_shown=2 WHERE id=1 AND warning_shown=0',
      );
    }
    if (evict) await _trim(limit, reserve: incoming);
    if (evict && (await stats())['bytes']! + incoming > limit * 1048576 * .8) {
      await db.execute('VACUUM');
    }
    Future<void> insert() => db.transaction((txn) async {
      final batch = txn.batch();
      final revisions = <String, int>{};
      for (final row in rows) {
        final id = row['id'] as String, kind = row['kind'] as String? ?? '';
        final old = await txn.query(
          'events',
          columns: ['edited_at'],
          where: 'id=?',
          whereArgs: [id],
          limit: 1,
        );
        final previous =
            revisions[id] ?? (old.isEmpty ? 0 : old.first['edited_at'] as int);
        if (row['deleted'] != true &&
            previous > (row['edited_at'] as int? ?? 0)) {
          continue;
        }
        revisions[id] = row['deleted'] == true
            ? 0
            : row['edited_at'] as int? ?? 0;
        if (_fts) {
          batch.rawDelete(
            'DELETE FROM search WHERE rowid IN (SELECT rowid FROM events WHERE id=?)',
            [id],
          );
        }
        batch.delete('events', where: 'id=?', whereArgs: [id]);
        if (row['deleted'] == true || (!text && kind.isEmpty)) continue;
        final body = text ? row['body'] as String? ?? '' : '';
        final value = <String, Object?>{
          'id': id,
          'room': row['room'],
          'time': row['time'],
          'kind': kind,
          'sender': row['sender'] ?? '',
          'body': body,
          'revision': row['revision'],
          'edited_at': row['edited_at'] ?? 0,
          'bytes': 512 + utf8.encode(jsonEncode(row)).length * 3,
        };
        batch.insert('events', value);
        if (_fts && body.isNotEmpty) {
          batch.rawInsert(
            'INSERT INTO search(rowid,id,room,body) SELECT rowid,id,room,body FROM events WHERE id=?',
            [id],
          );
        }
      }
      await batch.commit(noResult: true);
    });
    try {
      await insert();
    } on DatabaseException catch (e) {
      if (!evict) rethrow;
      if (!e.toString().contains('full') &&
          !e.toString().contains('no transaction is active')) {
        rethrow;
      }
      await _evict(500);
      await db.execute('VACUUM');
      await insert();
    }
    if (evict) await _trim(limit);
  }

  Future<void> _evict(int count) => database!.transaction((txn) async {
    if (_fts) {
      await txn.rawDelete(
        'DELETE FROM search WHERE rowid IN (SELECT rowid FROM events ORDER BY time ASC LIMIT ?)',
        [count],
      );
    }
    await txn.rawDelete(
      'DELETE FROM events WHERE id IN (SELECT id FROM events ORDER BY time ASC LIMIT ?)',
      [count],
    );
  });
  Future<void> _trim(int limit, {int reserve = 0}) async {
    for (var i = 0; i < 1000; i++) {
      final rows = await database!.query('history_totals', where: 'id=1');
      if (rows.first['n'] == 0) break;
      if ((rows.first['size'] as int) <= limit * 1024 * 1024 * .65 - reserve &&
          (rows.first['n'] as int) <= historyIndexEntryLimit(limit)) {
        break;
      }
      await _evict(500);
    }
  }

  Future<List<String>> query(
    String room, {
    required List<String> terms,
    String? kind,
    String? sender,
    int? before,
    int? after,
    required int offset,
    required int limit,
  }) async {
    final where = <String>['room=?'];
    final args = <Object?>[room];
    if (kind == 'media') {
      where.add("kind IN ('image','video')");
    } else if (kind == 'file') {
      where.add("kind IN ('image','video','audio','file')");
    } else if (kind != null) {
      where.add('kind=?');
      args.add(kind);
    }
    if (sender != null) {
      where.add('instr(lower(sender),?)>0');
      args.add(sender.toLowerCase());
    }
    if (before != null) {
      where.add('time < ?');
      args.add(before);
    }
    if (after != null) {
      where.add('time > ?');
      args.add(after);
    }
    if (terms.isNotEmpty && _fts && terms.every((t) => t.runes.length >= 3)) {
      where.add('id IN (SELECT id FROM search WHERE search MATCH ?)');
      args.add(terms.map((t) => '"${t.replaceAll('"', '""')}"').join(' AND '));
    } else {
      for (final term in terms) {
        where.add('instr(lower(body),?)>0');
        args.add(term.toLowerCase());
      }
    }
    final rows = await database!.query(
      'events',
      columns: ['id'],
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'time DESC,id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<Map<String, int>> stats() async {
    final total = (await database!.query(
      'history_totals',
      where: 'id=1',
    )).single;
    final pages = _sqliteInteger(
      (await database!.rawQuery('PRAGMA page_count')).first.values.first,
    );
    final size = _sqliteInteger(
      (await database!.rawQuery('PRAGMA page_size')).first.values.first,
    );
    final config = await settings();
    return {
      'entries': total['n'] as int,
      'bytes': pages * size,
      'budgetBytes': ((total['size'] as int) / .65).ceil(),
      'warning': config['warning'] as int? ?? 0,
    };
  }

  Future<void> clear() async {
    await saveDownloadState(null);
    await database!.delete('events');
    if (_fts) await database!.delete('search');
    await database!.execute('VACUUM');
    await database!.rawUpdate('UPDATE settings SET warning_shown=0 WHERE id=1');
  }

  Future<void> acknowledgeWarning() async =>
      database!.rawUpdate('UPDATE settings SET warning_shown=1 WHERE id=1');

  Future<Map<String, Object?>?> loadDownloadState() async {
    final rows = await database!.query('history_download', where: 'id=1');
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(
      jsonDecode(rows.single['state'] as String) as Map,
    );
  }

  Future<void> saveDownloadState(Map<String, Object?>? state) async {
    if (state == null) {
      await database!.delete('history_download');
      return;
    }
    final encoded = jsonEncode(state);
    if (utf8.encode(encoded).length > 3 * 1048576) {
      throw StateError('History progress is too large.');
    }
    await database!.insert('history_download', {
      'id': 1,
      'state': encoded,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> readRows(List<String> ids) async {
    if (ids.isEmpty) return [];
    if (ids.length > 200) throw ArgumentError('Too many search results');
    return database!.query(
      'events',
      columns: [
        'id',
        'room',
        'sender',
        'time',
        'kind',
        'body',
        'revision',
        'edited_at',
      ],
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<String?> revision(String id) async {
    final row = await database!.query(
      'events',
      columns: ['revision'],
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return row.isEmpty ? null : row.first['revision'] as String?;
  }

  Future<void> close() async => database?.close();
}
