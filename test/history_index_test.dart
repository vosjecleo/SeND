import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:deltiecord/services/history_index_native.dart';
import 'package:deltiecord/services/history_index_limits.dart';
import 'package:deltiecord/services/message_search.dart';

// SQLCipher on Android can return numeric PRAGMA results as text.
class _TextPragmaDatabase implements Database {
  _TextPragmaDatabase(this.inner);
  final Database inner;
  @override
  Future<void> execute(String sql, [List<Object?>? args]) =>
      inner.execute(sql, args);
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? args,
  ]) async {
    final rows = await inner.rawQuery(sql, args);
    return sql.startsWith('PRAGMA page_')
        ? rows
              .map(
                (r) => r.map((key, value) => MapEntry(key, value.toString())),
              )
              .toList()
        : rows;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );
  @override
  Future<void> close() => inner.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HistoryStore store;
  setUp(() async {
    sqfliteFfiInit();
    store = HistoryStore(
      'test',
      database: await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    await store.open();
  });
  tearDown(() => store.close());
  test(
    'stale originals cannot make archive quota checks subtract a retained newer edit',
    () async {
      await store.configure(true, 1);
      await store.put(
        [
          {
            'id': 'edited',
            'room': '!r:test',
            'sender': '@a:test',
            'time': 1,
            'kind': '',
            'body': 'x' * 140000,
            'edited_at': 10,
          },
        ],
        true,
        1,
      );
      expect(
        await store.putArchive(
          [
            {
              'id': 'edited',
              'room': '!r:test',
              'sender': '@a:test',
              'time': 1,
              'kind': '',
              'body': 'old',
              'edited_at': 0,
            },
            {
              'id': 'new',
              'room': '!r:test',
              'sender': '@a:test',
              'time': 2,
              'kind': '',
              'body': 'y' * 100000,
            },
          ],
          true,
          1,
        ),
        false,
      );
      expect((await store.readRows(['edited'])).single['edited_at'], 10);
      expect(await store.readRows(['new']), isEmpty);
    },
  );
  test(
    'archive quota refusal preserves old records and admits them after a larger limit',
    () async {
      await store.configure(true, 1);
      final old = {
        'id': 'old',
        'room': '!r:test',
        'sender': '@a:test',
        'time': 1,
        'kind': '',
        'body': 'keep this',
      };
      await store.put([old], true, 1);
      final large = {
        'id': 'large',
        'room': '!r:test',
        'sender': '@a:test',
        'time': 2,
        'kind': '',
        'body': 'x' * 300000,
      };
      expect(await store.putArchive([large], true, 1), false);
      expect((await store.readRows(['old'])).single['body'], 'keep this');
      expect(await store.readRows(['large']), isEmpty);
      await store.configure(true, 16);
      expect(await store.putArchive([large], true, 16), true);
      expect((await store.stats())['entries'], 2);
    },
  );
  test(
    'download progress persists separately and clears with indexed content',
    () async {
      final value = <String, Object?>{
        'version': 1,
        'rooms': ['!r:test'],
        'position': 0,
        'cursor': 'opaque-page',
      };
      await store.saveDownloadState(value);
      expect(await store.loadDownloadState(), value);
      await store.clear();
      expect(await store.loadDownloadState(), isNull);
    },
  );
  test(
    'larger byte budgets scale the entry ceiling without unbounded storage',
    () {
      expect(historyIndexEntryLimit(100), 100000);
      expect(historyIndexEntryLimit(250), 300000);
      expect(historyIndexEntryLimit(2048), 2100000);
      expect(historyIndexMaxMiB, 2048);
    },
  );
  test(
    'legacy full-text row IDs migrate and updates still remove old terms',
    () async {
      await store.configure(true, 100);
      await store.put(
        [
          {
            'id': 'legacy',
            'room': '!r:test',
            'sender': '@a:test',
            'time': 1,
            'kind': '',
            'body': 'firstword',
          },
        ],
        true,
        100,
      );
      final db = store.database!;
      await db.delete('search');
      await db.execute(
        "INSERT INTO search(rowid,id,room,body) SELECT 9000,id,room,body FROM events WHERE id='legacy'",
      );
      await db.execute('PRAGMA user_version=0');
      await store.open();
      final rows = await db.rawQuery(
        'SELECT e.rowid AS event_row, s.rowid AS search_row FROM events e JOIN search s ON e.id=s.id',
      );
      expect(rows.single['event_row'], rows.single['search_row']);
      await store.put(
        [
          {
            'id': 'legacy',
            'room': '!r:test',
            'sender': '@a:test',
            'time': 1,
            'kind': '',
            'body': 'secondword',
            'edited_at': 2,
          },
        ],
        true,
        100,
      );
      expect(
        await store.query(
          '!r:test',
          terms: ['firstword'],
          offset: 0,
          limit: 50,
        ),
        isEmpty,
      );
      expect(
        await store.query(
          '!r:test',
          terms: ['secondword'],
          offset: 0,
          limit: 50,
        ),
        ['legacy'],
      );
    },
  );
  test(
    'opening and measuring a store accepts Android text PRAGMA results',
    () async {
      store = HistoryStore(
        'test',
        database: _TextPragmaDatabase(store.database!),
      );
      await store.open();
      expect((await store.stats())['bytes'], greaterThan(0));
    },
  );
  test(
    'storage diagnostics expose codes without SQL, paths or bound values',
    () async {
      late DatabaseException error;
      try {
        await store.database!.rawQuery(
          'SELECT ? FROM private_table_diagnostic',
          ['secret-key'],
        );
      } catch (caught) {
        error = caught as DatabaseException;
      }
      expect(store.failureCode(error), 'SQLITE_1');
      expect(
        store.failureCode(StateError('protected store SQLITE_14')),
        'SQLITE_14',
      );
      expect(store.failureCode(StateError('secret-key')), 'StateError');
    },
  );
  Map<String, Object?> row(
    String id, {
    String body = 'hello world',
    String kind = '',
    int time = 1,
  }) => {
    'id': id,
    'room': '!r:test',
    'sender': '@a:test',
    'time': time,
    'kind': kind,
    'body': body,
  };
  Future<List<String>> query({
    List<String> terms = const [],
    String? kind,
    int offset = 0,
    int limit = 50,
  }) => store.query(
    '!r:test',
    terms: terms,
    kind: kind,
    offset: offset,
    limit: limit,
  );
  test('default index keeps media references but not message bodies', () async {
    expect((await store.settings())['enabled'], isNot(true));
    await store.put([row('text'), row('image', kind: 'image')], false, 50);
    expect(await query(), ['image']);
    final saved = await store.database!.query('events');
    expect(saved.single['body'], '');
    expect(
      saved.single.keys,
      unorderedEquals([
        'id',
        'room',
        'time',
        'kind',
        'sender',
        'body',
        'bytes',
        'revision',
        'edited_at',
      ]),
    );
    expect(await query(terms: ['hello']), isEmpty);
  });
  test('catalog kinds and selected Matrix IDs stay distinct', () async {
    await store.put(
      [
        {...row('image', kind: 'image'), 'sender': '@Alice:test'},
        {...row('file', kind: 'file'), 'sender': '@Alice:test'},
        {...row('audio', kind: 'audio'), 'sender': '@alice:test'},
      ],
      false,
      50,
    );
    expect(await query(kind: 'document'), unorderedEquals(['file', 'audio']));
    expect(await query(kind: 'media'), ['image']);
    expect(
      await store.query(
        '!r:test',
        terms: [],
        sender: '@Alice:test',
        offset: 0,
        limit: 50,
      ),
      unorderedEquals(['image', 'file']),
    );
  });
  test('all-terms search, edits, redactions and paging', () async {
    await store.configure(true, 25);
    await store.put(
      [
        row('a', body: 'hello distant world'),
        row('b', body: 'world hello', time: 2),
        row('c', body: 'no', time: 3),
      ],
      true,
      25,
    );
    expect(await query(terms: ['hello', 'world']), ['b', 'a']);
    expect(await query(limit: 1, offset: 1), ['b']);
    await store.put(
      [
        row('a', body: 'changed'),
        {...row('b'), 'deleted': true},
      ],
      true,
      25,
    );
    expect(await query(terms: ['hello']), isEmpty);
    expect(await query(terms: ['changed']), ['a']);
    await store.configure(false, 25);
    expect(await query(), isEmpty);
    expect((await store.settings())['enabled'], false);
    expect((await store.settings())['prompted'], true);
  });
  test('UI phrase queries match contiguous text in the native index', () async {
    await store.configure(true, 25);
    await store.put(
      [
        row('exact', body: 'Well, here you go!'),
        row('separated', body: 'here is something you can go to'),
        row('partial', body: 'lets go'),
      ],
      true,
      25,
    );
    expect(await query(terms: MessageSearchQuery.parse('here you go').terms), [
      'exact',
    ]);
  });
  test(
    'media-only and text opt-out remove all text from both stores',
    () async {
      await store.configure(true, 25);
      await store.put(
        [row('a', kind: 'image', body: 'secret caption')],
        true,
        25,
      );
      await store.configure(false, 25);
      expect(await query(kind: 'media'), ['a']);
      expect(await query(terms: ['secret']), isEmpty);
      expect((await store.database!.query('events')).single['body'], '');
      await store.clear();
      expect((await store.stats())['entries'], 0);
    },
  );
  test('an older page cannot overwrite an indexed edit', () async {
    await store.configure(true, 25);
    await store.put(
      [
        {...row('a', body: 'new words'), 'revision': 'edit', 'edited_at': 10},
        row('a', body: 'old words'),
      ],
      true,
      25,
    );
    expect(await query(terms: ['new']), ['a']);
    expect(await store.revision('a'), 'edit');
    await store.put([row('a', body: 'old words')], true, 25);
    expect(await query(terms: ['old']), isEmpty);
  });
  test(
    'warning survives pruning and is acknowledged until cache is cleared',
    () async {
      await store.configure(true, 1);
      await store.put(
        List.generate(220, (i) => row('$i', body: 'text ' * 220, time: i)),
        true,
        1,
      );
      expect((await store.stats())['warning'], 2);
      expect(await query(terms: ['text'], limit: 1000), isNot(contains('0')));
      expect(await query(terms: ['text'], limit: 1000), contains('219'));
      await store.acknowledgeWarning();
      expect((await store.stats())['warning'], 1);
      await store.clear();
      expect((await store.stats())['warning'], 0);
      expect((await store.stats())['entries'], 0);
    },
  );
  test('budget evicts oldest references and keeps newer records', () async {
    await store.configure(true, 16);
    for (var batch = 0; batch < 32; batch++) {
      await store.put(
        List.generate(
          50,
          (i) => row(
            '${batch * 50 + i}',
            kind: 'image',
            body: 'x' * 4000,
            time: batch * 50 + i,
          ),
        ),
        true,
        16,
      );
    }
    final result = await query(limit: 2000);
    expect(result.length, lessThan(1600));
    expect(result, contains('1599'));
    expect((await store.stats())['bytes'], lessThanOrEqualTo(16 * 1048576));
  });
}
