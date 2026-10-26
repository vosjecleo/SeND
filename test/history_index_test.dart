import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:deltiecord/services/history_index_native.dart';

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
