import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _keyName = 'send.desktop_database_key.v1';

/// SQLCipher from the checksum-pinned sqlite3 build hook. Never substitute the
/// system SQLite library, which would silently accept an ineffective PRAGMA key.
Future<Database> openEncryptedDesktopDatabase(
  String path, {
  Future<String?> Function()? readKey,
  Future<void> Function(String)? saveKey,
}) async {
  await Directory(File(path).parent.path).create(recursive: true);
  final lock = await File('$path.migration.lock').open(mode: FileMode.append);
  await lock.lock(FileLock.blockingExclusive);
  try {
    sqfliteFfiInit();
    final original = File(path);
    final temporary = File('$path.encrypted-migration');
    final backup = File('$path.migration-source');
    // Windows cannot rename over an existing file. Resume the exact interrupted
    // two-rename operation before permitting SQLite to create an empty store.
    if (!await original.exists() && await backup.exists()) {
      await backup.rename(path);
    }
    final exists = await original.exists();
    final plaintext = exists && await _plain(original);
    const storage = FlutterSecureStorage();
    var key = await (readKey?.call() ?? storage.read(key: _keyName));
    if (key == null) {
      if (exists && !plaintext && await original.length() > 0) {
        throw StateError(
          'The local database key is missing. Existing data has not been reset.',
        );
      }
      final random = Random.secure();
      key = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
      await (saveKey?.call(key) ?? storage.write(key: _keyName, value: key));
      if (await (readKey?.call() ?? storage.read(key: _keyName)) != key) {
        throw StateError('Could not protect the local database key.');
      }
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{43}=$').hasMatch(key)) {
      throw StateError('Invalid local database key.');
    }
    Future<Database> open(String filename, {bool encrypted = true}) =>
        databaseFactoryFfi.openDatabase(
          filename,
          options: OpenDatabaseOptions(
            singleInstance: false,
            onConfigure: (db) async {
              if ((await db.rawQuery('PRAGMA cipher_version')).isEmpty) {
                throw StateError(
                  'SQLCipher is unavailable. Refusing unprotected storage.',
                );
              }
              if (encrypted) await db.execute("PRAGMA key='$key'");
              // Let transient concurrent opens/writes settle rather than
              // immediately failing key-backup or settings updates with BUSY.
              await db.execute('PRAGMA busy_timeout=5000');
              await db.execute('PRAGMA temp_store=MEMORY');
              await db.execute('PRAGMA cipher_memory_security=ON');
              await db.rawQuery('SELECT count(*) FROM sqlite_master');
            },
          ),
        );
    if (plaintext) {
      if (await temporary.exists()) await temporary.delete();
      final source = await open(path, encrypted: false);
      try {
        await source.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        await source.rawQuery('PRAGMA journal_mode=DELETE');
        final version = await source.getVersion();
        await source.execute('ATTACH DATABASE ? AS encrypted KEY ?', [
          temporary.path,
          key,
        ]);
        try {
          await source.rawQuery("SELECT sqlcipher_export('encrypted')");
          await source.execute('PRAGMA encrypted.user_version=$version');
        } finally {
          await source.execute('DETACH DATABASE encrypted');
        }
      } finally {
        await source.close();
      }
      final checked = await open(temporary.path);
      try {
        final result = await checked.rawQuery('PRAGMA integrity_check');
        if (result.length != 1 || result.single.values.single != 'ok') {
          throw StateError('Database verification failed.');
        }
      } finally {
        await checked.close();
      }
      if (Platform.isWindows) {
        if (await backup.exists()) {
          throw StateError(
            'An earlier migration source must be recovered first.',
          );
        }
        await original.rename(backup.path);
        try {
          await temporary.rename(path);
        } catch (_) {
          await backup.rename(path);
          rethrow;
        }
      } else {
        await temporary.rename(path);
      }
    }
    final database = await open(path);
    // Retain an interrupted source until the actual final file has opened with
    // its protected key. Do not leave a plaintext migration backup afterwards.
    if (await backup.exists()) await backup.delete();
    return database;
  } catch (error) {
    throw StateError(
      'Could not open protected local storage. Existing data has not been reset. '
      'SQLITE_${error is DatabaseException ? error.getResultCode() ?? 0 : 0}',
    );
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<bool> _plain(File file) async {
  final input = await file.open();
  try {
    return latin1.decode(await input.read(16)) == 'SQLite format 3\u0000';
  } finally {
    await input.close();
  }
}
