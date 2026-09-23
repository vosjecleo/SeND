import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

const _keyName = 'deltiecord.matrix_database_key.v1';

/// Android's Keystore protects the randomly generated SQLCipher password.
/// Missing keys or failed migrations must never silently reset a Matrix store.
Future<cipher.Database> openEncryptedAndroidDatabase(String path) async {
  final lock = await File('$path.migration.lock').open(mode: FileMode.append);
  await lock.lock(FileLock.blockingExclusive);
  try {
    final file = File(path);
    final exists = await file.exists();
    var plaintext = false;
    if (exists) {
      final handle = await file.open();
      try {
        plaintext =
            latin1.decode(await handle.read(16)) == 'SQLite format 3\u0000';
      } finally {
        await handle.close();
      }
    }
    const storage = FlutterSecureStorage();
    var key = await storage.read(key: _keyName);
    if (key == null) {
      if (exists && !plaintext) {
        throw StateError(
          'The encrypted local database key is unavailable. Restore access to this device’s secure storage; the database has not been deleted.',
        );
      }
      final random = Random.secure();
      key = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
      await storage.write(key: _keyName, value: key);
      if (await storage.read(key: _keyName) != key) {
        throw StateError('Could not protect the local database key.');
      }
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{43}=$').hasMatch(key)) {
      throw StateError('Invalid local database key.');
    }
    try {
      if (plaintext) await _migrate(path, key);
      final database = await cipher.openDatabase(path, password: key);
      try {
        await _verify(database, thorough: false);
        return database;
      } catch (_) {
        await database.close();
        rethrow;
      }
    } catch (_) {
      // SQL plugin exceptions may include bound arguments (including the key).
      // Never surface those through the app's generic startup error reporting.
      throw StateError(
        'Could not open or migrate the protected local database. Existing data has not been reset.',
      );
    }
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<void> _verify(cipher.Database database, {bool thorough = true}) async {
  if ((await database.rawQuery('PRAGMA cipher_version')).isEmpty) {
    throw StateError('SQLCipher is unavailable; refusing plaintext storage.');
  }
  if (!thorough) {
    await database.rawQuery('SELECT count(*) FROM sqlite_master');
    return;
  }
  final integrity = await database.rawQuery('PRAGMA integrity_check');
  if (integrity.length != 1 || integrity.single.values.single != 'ok') {
    throw StateError('Local database integrity check failed.');
  }
}

Future<void> _migrate(String path, String key) async {
  final temporary = File('$path.encrypted-migration');
  // Only our exact interrupted export is removed; the source stays untouched
  // until a closed, decrypted/readable replacement has passed integrity checks.
  if (await temporary.exists()) await temporary.delete();
  final source = await cipher.openDatabase(path);
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
  final replacement = await cipher.openDatabase(temporary.path, password: key);
  try {
    await _verify(replacement);
  } finally {
    await replacement.close();
  }
  // Android/POSIX rename replaces the closed source atomically. No plaintext
  // backup is retained. The Keystore key was persisted before export began.
  await temporary.rename(path);
}
