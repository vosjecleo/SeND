// Storage interface adapted from Matrix Dart SDK 10.1.0 (Famedly GmbH).
// SPDX-License-Identifier: AGPL-3.0-or-later
// Encrypted values AND opaque HMAC keys. Schema names/counts remain structural
// metadata. Crypto preparation happens before IDB write transactions begin.
import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart';
// Pinned SDK transaction context; keep parity with its concrete database API.
// ignore: implementation_imports
import 'package:matrix/src/database/zone_transaction_mixin.dart';
import 'vault.dart';

Future<JSAny?> _result(IDBRequest request) {
  final completed = Completer<JSAny?>();
  request.onsuccess = ((Event _) {
    completed.complete(request.result);
  }).toJS;
  request.onerror = ((Event _) {
    completed.completeError(StateError('Protected database request failed.'));
  }).toJS;
  return completed.future;
}

Future<void> _done(IDBTransaction tx) {
  final completed = Completer<void>();
  tx.oncomplete = ((Event _) {
    completed.complete();
  }).toJS;
  void failed(Event _) {
    if (!completed.isCompleted) {
      completed.completeError(
        StateError('Protected database transaction failed.'),
      );
    }
  }

  tx.onabort = failed.toJS;
  tx.onerror = failed.toJS;
  return completed.future;
}

class _Write {
  const _Write(this.store, this.kind, [this.key, this.value]);
  final String store, kind;
  final String? key;
  final JSAny? value;
}

class BoxCollection with ZoneTransactionMixin {
  BoxCollection(this._db, this.boxNames, this.name)
    : vault = WebRecordVault('matrix:$name');
  final IDBDatabase _db;
  final Set<String> boxNames;
  final String name;
  final WebRecordVault vault;
  final _boxes = <String, Box>{};
  List<Future<_Write> Function()>? _pending;
  Zone? _owner;
  bool get _insideTransaction {
    for (Zone? zone = Zone.current; zone != null; zone = zone.parent) {
      if (identical(zone, _owner)) return true;
    }
    return false;
  }

  Future<T> locked<T>(Future<T> Function() action) async {
    late T result;
    await zoneTransaction(() async {
      result = await action();
    });
    return result;
  }

  static const _meta = 'send_encryption_v1';
  static Future<BoxCollection> open(
    String name,
    Set<String> boxNames, {
    Object? sqfliteDatabase,
    Object? sqfliteFactory,
    IDBFactory? idbFactory,
    int version = 1,
  }) async {
    final factory = idbFactory ?? window.indexedDB;
    final completed = Completer<IDBDatabase>();
    final request = factory.open(name, version * 100 + 1);
    request.onupgradeneeded = ((IDBVersionChangeEvent _) {
      final db = request.result as IDBDatabase;
      for (final box in {...boxNames, _meta}) {
        if (!db.objectStoreNames.contains(box)) {
          db.createObjectStore(
            box,
            IDBObjectStoreParameters(autoIncrement: true),
          );
        }
      }
    }).toJS;
    request.onblocked = ((Event _) {
      if (!completed.isCompleted) {
        completed.completeError(
          StateError(
            'Close other SeND tabs before upgrading protected storage.',
          ),
        );
      }
    }).toJS;
    request.onerror = ((Event _) {
      if (!completed.isCompleted) {
        completed.completeError(
          StateError(
            'Protected database could not be opened. Existing data was kept.',
          ),
        );
      }
    }).toJS;
    request.onsuccess = ((Event _) {
      final db = request.result as IDBDatabase;
      if (completed.isCompleted) {
        db.close();
        return;
      }
      completed.complete(db);
    }).toJS;
    final db = await completed.future;
    db.onversionchange = ((IDBVersionChangeEvent _) => db.close()).toJS;
    final collection = BoxCollection(db, boxNames, name);
    try {
      final raw = (await _result(
        db
            .transaction(_meta.toJS, 'readonly')
            .objectStore(_meta)
            .get('key'.toJS),
      ))?.dartify();
      if (raw == null) {
        for (final store in boxNames) {
          final first =
              (await _result(
                    db
                        .transaction(store.toJS, 'readonly')
                        .objectStore(store)
                        .getAll(null, 1),
                  ))?.dartify()
                  as List? ??
              [];
          if (first.isNotEmpty &&
              first.first is Map &&
              (first.first as Map)['sendEncrypted'] == 1) {
            throw StateError(
              'Local encryption marker is missing. Existing data was kept.',
            );
          }
        }
      }
      final id = await collection.vault.bind(raw is String ? raw : null);
      final tx = db.transaction(_meta.toJS, 'readwrite'), done = _done(tx);
      tx.objectStore(_meta).put(id.toJS, 'key'.toJS);
      await done;
      final migrated = (await _result(
        db
            .transaction(_meta.toJS, 'readonly')
            .objectStore(_meta)
            .get('migrated'.toJS),
      ))?.dartify();
      if (migrated != true) {
        await collection._migrate();
        final finished = db.transaction(_meta.toJS, 'readwrite'),
            saved = _done(finished);
        finished.objectStore(_meta).put(true.toJS, 'migrated'.toJS);
        await saved;
      }
      return collection;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  Future<void> _migrate() async {
    for (final storeName in boxNames) {
      // Read fixed-size pages so old timelines cannot cause a large RAM spike.
      JSAny? after;
      while (true) {
        final tx = _db.transaction(storeName.toJS, 'readonly'),
            store = tx.objectStore(storeName);
        final range = after == null
            ? null
            : IDBKeyRange.lowerBound(after, true);
        final keyRequest = store.getAllKeys(range, 32),
            valueRequest = store.getAll(range, 32);
        final raw = await Future.wait([
          _result(keyRequest),
          _result(valueRequest),
        ]);
        final keys = (raw[0]?.dartify() as List?) ?? [];
        final values = (raw[1]?.dartify() as List?) ?? [];
        if (keys.isEmpty) break;
        final writes = <_Write>[];
        for (var i = 0; i < keys.length; i++) {
          final key = '${keys[i]}', value = values[i];
          if (value is Map && value['sendEncrypted'] == 1) {
            // Authenticate existing encrypted rows too, never downgrade them.
            await vault.open(storeName, key, value.jsify());
            continue;
          }
          final hidden = await vault.hash(storeName, key);
          final sealed = await vault.seal(storeName, hidden, {
            'key': key,
            'value': value,
          });
          await vault.open(storeName, hidden, sealed);
          writes.add(_Write(storeName, 'put', hidden, sealed));
          if (hidden != key) writes.add(_Write(storeName, 'delete', key));
        }
        if (writes.isNotEmpty) await _commit(writes);
        after = (keys.last as Object?).jsify();
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Box<V> openBox<V>(String store) {
    if (!boxNames.contains(store)) throw StateError('Unknown protected store.');
    return _boxes.putIfAbsent(store, () => Box<V>(store, this)) as Box<V>;
  }

  Future<void> _commit(List<_Write> writes) async {
    if (writes.isEmpty) return;
    final names = writes.map((w) => w.store).toSet().toList();
    final tx = _db.transaction(names.jsify()!, 'readwrite'), done = _done(tx);
    try {
      for (final write in writes) {
        final store = tx.objectStore(write.store);
        switch (write.kind) {
          case 'put':
            store.put(write.value, write.key!.toJS);
          case 'delete':
            store.delete(write.key!.toJS);
          case 'clear':
            store.clear();
        }
      }
    } catch (_) {
      tx.abort();
      try {
        await done;
      } catch (_) {
        /* The original write error is reported below. */
      }
      rethrow;
    }
    await done;
  }

  Future<void> transaction(
    Future<void> Function() action, {
    List<String>? boxNames,
    bool readOnly = false,
  }) {
    if (_insideTransaction) return action();
    return zoneTransaction(() async {
      _owner = Zone.current;
      final work = _pending = <Future<_Write> Function()>[];
      try {
        await action();
        _pending = null;
        await _commit(await Future.wait(work.map((prepare) => prepare())));
      } catch (_) {
        for (final box in _boxes.values) {
          box.clearQuickAccessCache();
        }
        rethrow;
      } finally {
        _pending = null;
        _owner = null;
        for (final box in _boxes.values) {
          box._finish();
        }
      }
    });
  }

  Future<void> clear() async {
    await transaction(() async {
      _pending!.addAll([
        for (final store in boxNames) () async => _Write(store, 'clear'),
      ]);
      for (final box in _boxes.values) {
        box._cache.clear();
        box._changes.clear();
        box._cleared = true;
      }
    });
  }

  Future<void> close() async {
    _db.close();
  }

  static Future<void> delete(String name, [dynamic factory]) async {
    await _result(
      ((factory ?? window.indexedDB) as IDBFactory).deleteDatabase(name),
    );
  }

  Future<void> deleteDatabase(String name, [dynamic factory]) async {
    await close();
    await delete(name, factory);
  }
}

class Box<V> {
  Box(this.name, this.collection);
  final String name;
  final BoxCollection collection;
  final _cache = <String, V?>{};
  final _changes = <String, V?>{};
  bool _cleared = false;
  void _finish() {
    _changes.clear();
    _cleared = false;
  }

  Future<Map<String, V>> getAllValues([IDBTransaction? ignored]) =>
      collection.locked(() async {
        final store = collection._db
            .transaction(name.toJS, 'readonly')
            .objectStore(name);
        final results = await Future.wait([
          _result(store.getAllKeys()),
          _result(store.getAll()),
        ]);
        final keys = results[0]?.dartify() as List? ?? [];
        final raw = results[1]?.dartify() as List? ?? [];
        final result = <String, V>{};
        for (var i = 0; i < raw.length; i++) {
          final hidden = keys[i] as String;
          final decoded =
              await collection.vault.open(
                    name,
                    hidden,
                    (raw[i] as Object?).jsify(),
                  )
                  as Map;
          final key = decoded['key'] as String;
          if (await collection.vault.hash(name, key) != hidden) {
            throw StateError('Protected lookup mismatch.');
          }
          result[key] = _value(decoded['value']) as V;
        }
        if (_cleared) result.clear();
        for (final entry in _changes.entries) {
          if (entry.value == null) {
            result.remove(entry.key);
          } else {
            result[entry.key] = entry.value as V;
          }
        }
        _cache.addAll(result);
        return result;
      });
  Future<List<String>> getAllKeys([IDBTransaction? ignored]) async =>
      (await getAllValues()).keys.toList();
  Future<V?> get(String key, [IDBTransaction? ignored]) => collection.locked(
    () async {
      if (_cache.containsKey(key)) return _cache[key];
      if (_cleared) return null;
      final hidden = await collection.vault.hash(name, key);
      final raw = await _result(
        collection._db
            .transaction(name.toJS, 'readonly')
            .objectStore(name)
            .get(hidden.toJS),
      );
      if (raw == null) return _cache[key] = null;
      final decoded = await collection.vault.open(name, hidden, raw) as Map;
      if (decoded['key'] != key) throw StateError('Protected lookup mismatch.');
      return _cache[key] = _value(decoded['value']);
    },
  );
  Future<List<V?>> getAll(List<String> keys, [IDBTransaction? ignored]) =>
      Future.wait(keys.map((key) => get(key)));
  Future<void> put(String key, V value, [IDBTransaction? ignored]) =>
      collection.transaction(() async {
        collection._pending!.add(() async {
          final hidden = await collection.vault.hash(name, key);
          return _Write(
            name,
            'put',
            hidden,
            await collection.vault.seal(name, hidden, {
              'key': key,
              'value': value,
            }),
          );
        });
        _cache[key] = value;
        _changes[key] = value;
      });
  Future<void> delete(String key, [IDBTransaction? ignored]) =>
      collection.transaction(() async {
        collection._pending!.add(
          () async =>
              _Write(name, 'delete', await collection.vault.hash(name, key)),
        );
        _cache[key] = null;
        _changes[key] = null;
      });
  Future<void> deleteAll(List<String> keys, [IDBTransaction? ignored]) =>
      collection.transaction(() async {
        for (final key in keys) {
          await delete(key);
        }
      });
  void clearQuickAccessCache() => _cache.clear();
  Future<void> clear([IDBTransaction? ignored]) =>
      collection.transaction(() async {
        collection._pending!.add(() async => _Write(name, 'clear'));
        _cache.clear();
        _changes.clear();
        _cleared = true;
      });
  V? _value(Object? value) {
    if (value == null) return null;
    if (V == int && value is double) return value.round() as V;
    if (value is List) return List.unmodifiable(value) as V;
    if (value is Map) return Map.unmodifiable(value) as V;
    return value as V;
  }
}
