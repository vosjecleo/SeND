import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:deltiecord/matrix/encrypted_desktop_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'migration preserves session rows and FTS, leaving no plaintext backup',
    () async {
      sqfliteFfiInit();
      final folder = await Directory.systemTemp.createTemp('send-cipher-test-');
      addTearDown(() => folder.delete(recursive: true));
      final path = '${folder.path}/data.db';
      var source = await databaseFactoryFfi.openDatabase(path);
      await source.execute('CREATE TABLE sessions(value TEXT)');
      await source.rawInsert('INSERT INTO sessions VALUES(?)', [
        'private session',
      ]);
      await source.execute('CREATE VIRTUAL TABLE search USING fts5(body)');
      await source.rawInsert('INSERT INTO search VALUES(?)', [
        'private message',
      ]);
      await source.setVersion(11);
      await source.close();
      String? key;
      Future<Database> open() => openEncryptedDesktopDatabase(
        path,
        readKey: () async => key,
        saveKey: (value) async {
          key = value;
        },
      );
      final protected = await open();
      expect(await protected.getVersion(), 11);
      expect(
        (await protected.rawQuery('PRAGMA busy_timeout')).single.values.single,
        5000,
      );
      expect(
        (await protected.rawQuery(
          'SELECT value FROM sessions',
        )).single['value'],
        'private session',
      );
      expect(
        (await protected.rawQuery(
          "SELECT body FROM search WHERE search MATCH 'message'",
        )).single['body'],
        'private message',
      );
      expect(
        (await protected.rawQuery('PRAGMA temp_store')).single.values.single,
        2,
      );
      await protected.close();
      expect(
        latin1.decode(await File(path).readAsBytes()),
        isNot(contains('private session')),
      );
      expect(
        latin1.decode((await File(path).readAsBytes()).take(16).toList()),
        isNot('SQLite format 3\u0000'),
      );
      expect(await File('$path.migration-source').exists(), false);
      final reopened = await open();
      await reopened.close();
      await expectLater(
        openEncryptedDesktopDatabase(
          path,
          readKey: () async => null,
          saveKey: (_) async => fail('must not replace key'),
        ),
        throwsStateError,
      );
      final restored = await open();
      expect(
        (await restored.rawQuery(
          'SELECT count(*) AS n FROM sessions',
        )).single['n'],
        1,
      );
      await restored.close();
    },
  );
  test('wrong key does not reset the encrypted database', () async {
    final folder = await Directory.systemTemp.createTemp(
      'send-cipher-key-test-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/data.db';
    final key = base64UrlEncode(List.filled(32, 7));
    var db = await openEncryptedDesktopDatabase(path, readKey: () async => key);
    await db.execute('CREATE TABLE kept(value TEXT)');
    await db.close();
    await expectLater(
      openEncryptedDesktopDatabase(
        path,
        readKey: () async => base64UrlEncode(List.filled(32, 8)),
      ),
      throwsStateError,
    );
    db = await openEncryptedDesktopDatabase(path, readKey: () async => key);
    expect(
      await db.rawQuery("SELECT name FROM sqlite_master WHERE name='kept'"),
      hasLength(1),
    );
    await db.close();
  });
}
