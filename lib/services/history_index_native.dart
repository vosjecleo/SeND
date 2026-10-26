import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../matrix/encrypted_android_database.dart';
import 'private_file_store.dart';

class HistoryStore {
  HistoryStore(this.account, {this.database});
  final String account;
  Database? database;
  bool _fts = false;
  Future<void> open() async {
    if (database == null) {
      final folder = Directory(
        '${(await getApplicationSupportDirectory()).path}/deltiecord/search',
      );
      await ensurePrivateDirectory(folder);
      final path = '${folder.path}/$account.db';
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
    await db.execute(
      'CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY, enabled INTEGER, prompted INTEGER, budget INTEGER)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, room TEXT NOT NULL, time INTEGER NOT NULL, kind TEXT NOT NULL, sender TEXT NOT NULL, body TEXT NOT NULL, bytes INTEGER NOT NULL)',
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
    try {
      await db.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(id UNINDEXED, room UNINDEXED, body, tokenize='trigram')",
      );
      _fts = true;
    } catch (_) {
      _fts = false;
    }
    final config = await settings();
    final limit = (config['limit'] as int? ?? 50).clamp(16, 250);
    final pages =
        (await db.rawQuery('PRAGMA page_size')).first.values.first as int;
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
    };
  }

  Future<void> configure(bool enabled, int limit) async {
    final db = database!;
    await db.insert('settings', {
      'id': 1,
      'enabled': enabled ? 1 : 0,
      'prompted': 1,
      'budget': limit,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (!enabled) {
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
    final pages =
        (await db.rawQuery('PRAGMA page_size')).first.values.first as int;
    await db.rawQuery(
      'PRAGMA max_page_count = ${limit * 1024 * 1024 ~/ pages}',
    );
  }

  Future<void> put(
    List<Map<String, Object?>> rows,
    bool text,
    int limit,
  ) async {
    final db = database!;
    if (rows.length > 32) {
      for (var i = 0; i < rows.length; i += 32) {
        await put(rows.skip(i).take(32).toList(), text, limit);
      }
      return;
    }
    // Leave room for FTS segments, indexes and transaction bookkeeping rather
    // than waiting for SQLite's hard cap to abort a transaction mid-batch.
    final incoming = rows.fold<int>(
      0,
      (n, row) => n + 1024 + utf8.encode(jsonEncode(row)).length * 3,
    );
    await _trim(limit, reserve: incoming);
    if ((await stats())['bytes']! + incoming > limit * 1048576 * .8) {
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
        batch.delete('events', where: 'id=?', whereArgs: [id]);
        if (_fts) batch.delete('search', where: 'id=?', whereArgs: [id]);
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
          batch.insert('search', {'id': id, 'room': row['room'], 'body': body});
        }
      }
      await batch.commit(noResult: true);
    });
    try {
      await insert();
    } on DatabaseException catch (e) {
      if (!e.toString().contains('full') &&
          !e.toString().contains('no transaction is active')) {
        rethrow;
      }
      await _evict(500);
      await db.execute('VACUUM');
      await insert();
    }
    await _trim(limit);
  }

  Future<void> _evict(int count) => database!.transaction((txn) async {
    if (_fts) {
      await txn.rawDelete(
        'DELETE FROM search WHERE id IN (SELECT id FROM events ORDER BY time ASC LIMIT ?)',
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
      final rows = await database!.rawQuery(
        'SELECT COALESCE(SUM(bytes),0) AS size,COUNT(*) AS n FROM events',
      );
      if ((rows.first['size'] as int) <= limit * 1024 * 1024 * .65 - reserve &&
          (rows.first['n'] as int) <= 100000) {
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
    final count =
        (await database!.rawQuery(
              'SELECT COUNT(*) AS n FROM events',
            )).first['n']
            as int;
    final pages =
        (await database!.rawQuery('PRAGMA page_count')).first.values.first
            as int;
    final size =
        (await database!.rawQuery('PRAGMA page_size')).first.values.first
            as int;
    return {'entries': count, 'bytes': pages * size};
  }

  Future<void> clear() async {
    await database!.delete('events');
    if (_fts) await database!.delete('search');
    await database!.execute('VACUUM');
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
