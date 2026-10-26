import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/services/personal_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<PersonalData> open(String account, Map<String, Object?> remote) async {
    final data = PersonalData(
      account: account,
      write: (key, value) async => remote[key] = value,
    );
    await data.open(remote);
    addTearDown(data.close);
    return data;
  }

  test(
    'account data merges offline changes, removals and replay-safe usage',
    () async {
      final records = <String, Object?>{};
      final a = await open('@one:test', records);
      await a.set('fav.emoji:🙂', true);
      await a.set('pin:!r:test', true);
      await a.recordUsage('emoji', '🙂');
      await a.flush();
      final first = Map<String, Object?>.from(records);
      FlutterSecureStorage.setMockInitialValues({});
      final b = await open('@one:test', records);
      expect(b.eventType, isNot(a.eventType));
      expect(b.favourites('emoji'), ['🙂']);
      await b.set('fav.emoji:🙂', false);
      await b.set('archive:!other:test', true);
      await b.recordUsage('emoji', '🙂');
      await b.flush();
      a.merge(records);
      a.merge(records);
      expect(a.favourites('emoji'), isEmpty);
      expect(a.usage('emoji')['🙂'], 2);
      expect(a.pinned('!r:test'), true);
      expect(a.archived('!other:test'), true);
      // A stale echo of our own record must not replace a later local edit.
      await a.set('pin:!r:test', false);
      a.merge(first);
      expect(a.pinned('!r:test'), false);
    },
  );
  test(
    'settings stay isolated by account and survive restart without network',
    () async {
      final a = await open('@one:test', {});
      await a.set('folder:one', 'Friends');
      await a.set('folderOf:!space:test', 'one');
      final b = await open('@two:test', {});
      expect(b.folders, isEmpty);
      final resumed = await open('@one:test', {});
      expect(resumed.folderFor('!space:test'), 'one');
      await resumed.set('folder:one', null);
      expect(resumed.folderFor('!space:test'), isNull);
    },
  );
  test('failed publication retains local settings for later retry', () async {
    final data = PersonalData(
      account: '@one:test',
      write: (_, _) async => throw StateError('offline'),
    );
    await data.open({});
    await data.set('archive:!r:test', true);
    await data.flush();
    expect(data.warning, isNotNull);
    await data.close();
    final resumed = await open('@one:test', {});
    expect(resumed.archived('!r:test'), true);
  });
}
