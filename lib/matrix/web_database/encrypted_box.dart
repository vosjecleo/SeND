// Storage interface adapted from Matrix Dart SDK 10.1.0 (Famedly GmbH).
// SPDX-License-Identifier: AGPL-3.0-or-later
// Encrypted values AND opaque HMAC keys. Schema names/counts remain structural
// metadata. Crypto preparation happens before IDB write transactions begin.
import 'dart:async';
import 'dart:convert';
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
  final _scopeHashes = <(String, String), Future<String>>{};
  Future<String> _scopeHash(String store, String scope) {
    final lookup = (store, scope);
    final cached = _scopeHashes.remove(lookup);
    if (cached != null) {
      _scopeHashes[lookup] = cached;
      return cached;
    }
    if (_scopeHashes.length >= 512) {
      _scopeHashes.remove(_scopeHashes.keys.first);
    }
    final result = vault.hash(store, scope);
    _scopeHashes[lookup] = result;
    return result;
  }

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
  static String _keyStore(String name) => '${name}__keys_v1';
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
    final request = factory.open(name, version * 100 + 2);
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
      for (final box in boxNames) {
        final keys = _keyStore(box);
        if (!db.objectStoreNames.contains(keys)) {
          db.createObjectStore(keys).createIndex('scope', 'scope'.toJS);
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
      if (raw != null && (raw is! String || raw.isEmpty)) {
        throw StateError(
          'Local encryption marker is invalid. Existing data was kept.',
        );
      }
      if (raw == null) {
        if (await collection._hasEncryptedRows()) {
          throw StateError(
            'Local encryption marker is missing. Existing data was kept.',
          );
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
      final indexed = (await _result(
        db
            .transaction(_meta.toJS, 'readonly')
            .objectStore(_meta)
            .get('keyIndex'.toJS),
      ))?.dartify();
      if (migrated != true || indexed != true) {
        await collection._migrate();
        final finished = db.transaction(_meta.toJS, 'readwrite'),
            saved = _done(finished);
        finished.objectStore(_meta).put(true.toJS, 'migrated'.toJS);
        finished.objectStore(_meta).put(true.toJS, 'keyIndex'.toJS);
        await saved;
      }
      return collection;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  Future<bool> _hasEncryptedRows() async {
    // An interrupted old migration can have plaintext first and encrypted rows
    // later. Inspect every page before binding any replacement key. Healthy
    // encrypted databases already have a marker and never need this scan.
    for (final name in boxNames) {
      JSAny? after;
      while (true) {
        final store = _db.transaction(name.toJS, 'readonly').objectStore(name);
        final range = after == null
            ? null
            : IDBKeyRange.lowerBound(after, true);
        final page = await Future.wait([
          _result(store.getAllKeys(range, 128)),
          _result(store.getAll(range, 128)),
        ]);
        final keys = page[0]?.dartify() as List? ?? [];
        final values = page[1]?.dartify() as List? ?? [];
        if (values.any(
          (value) => value is Map && value['sendEncrypted'] == 1,
        )) {
          return true;
        }
        if (keys.isEmpty) break;
        after = (keys.last as Object?).jsify();
      }
    }
    return false;
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
            final decoded =
                await vault.open(storeName, key, value.jsify()) as Map;
            final logical = decoded['key'] as String;
            if (await vault.hash(storeName, logical) != key) {
              throw StateError('Protected lookup mismatch.');
            }
            writes.add(await _prepareKey(storeName, logical, key));
            continue;
          }
          final hidden = await vault.hash(storeName, key);
          final sealed = await vault.seal(storeName, hidden, {
            'key': key,
            'value': value,
          });
          await vault.open(storeName, hidden, sealed);
          writes.add(_Write(storeName, 'put', hidden, sealed));
          writes.add(await _prepareKey(storeName, key, hidden));
          if (hidden != key) writes.add(_Write(storeName, 'delete', key));
        }
        if (writes.isNotEmpty) await _commit(writes);
        after = (keys.last as Object?).jsify();
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<_Write> _prepareKey(String store, String key, String hidden) async {
    final keys = _keyStore(store);
    final scope = await _scopeHash(keys, key.split('|').first);
    return _Write(
      keys,
      'put',
      hidden,
      {
        'scope': scope,
        'sealed': await vault.seal(keys, hidden, {'key': key, 'scope': scope}),
      }.jsify(),
    );
  }

  Box<V> openBox<V>(String store) {
    if (!boxNames.contains(store)) throw StateError('Unknown protected store.');
    return _boxes.putIfAbsent(store, () => Box<V>(store, this)) as Box<V>;
  }

  /// Capture all stores in one read-only IDB transaction. Decrypt afterwards,
  /// so another tab's atomic write cannot produce a mixed-version export.
  Future<Map<String, Object?>> snapshot() => locked(() async {
    final tx = _db.transaction(boxNames.toList().jsify()!, 'readonly');
    final done = _done(tx);
    final reads = <String, Future<List<JSAny?>>>{};
    for (final name in boxNames) {
      final store = tx.objectStore(name);
      reads[name] = Future.wait([
        _result(store.getAllKeys()),
        _result(store.getAll()),
      ]);
    }
    final raw = await Future.wait([
      ...reads.values,
      done.then((_) => <JSAny?>[]),
    ]);
    final result = <String, Object?>{};
    for (final (i, name) in reads.keys.indexed) {
      final box = _boxes[name] ?? Box<Object?>(name, this);
      result[name] = await box._decodeValues(raw[i]);
    }
    return result;
  });

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
        for (final store in boxNames) ...[
          () async => _Write(store, 'clear'),
          () async => _Write(_keyStore(store), 'clear'),
        ],
      ]);
      for (final box in _boxes.values) {
        box.clearQuickAccessCache();
        box._changes.clear();
        box._cleared = true;
      }
    });
  }

  Future<void> close() async {
    _scopeHashes.clear();
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
  final _cacheSizes = <String, int>{};
  int _cacheBytes = 0;
  static const maximumCachedRecords = 128;
  static const maximumCachedBytes = 512 * 1024;
  int get cachedRecordCount => _cache.length;
  int get cachedBytes => _cacheBytes;
  final _changes = <String, V?>{};
  bool _cleared = false;
  void _finish() {
    _changes.clear();
    _cleared = false;
  }

  V? _remember(String key, V? value) {
    _cache.remove(key);
    _cacheBytes -= _cacheSizes.remove(key) ?? 0;
    final size = key.length * 2 + jsonEncode(value).length * 2 + 64;
    if (size > maximumCachedBytes) return value;
    while (_cache.isNotEmpty &&
        (_cache.length >= maximumCachedRecords ||
            _cacheBytes + size > maximumCachedBytes)) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _cacheBytes -= _cacheSizes.remove(oldest)!;
    }
    _cache[key] = value;
    _cacheSizes[key] = size;
    _cacheBytes += size;
    return value;
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
        return _decodeValues(results);
      });

  Future<Map<String, V>> _decodeValues(List<JSAny?> results) async {
    final keys = results[0]?.dartify() as List? ?? [];
    final raw = results[1]?.dartify() as List? ?? [];
    final result = <String, V>{};
    for (var i = 0; i < raw.length; i++) {
      final hidden = keys[i] as String;
      final decoded =
          await collection.vault.open(name, hidden, (raw[i] as Object?).jsify())
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
    return result;
  }

  Future<List<String>> getAllKeys([IDBTransaction? ignored]) => _keys();

  /// Tuple-key collections are partitioned by their first component (room or
  /// user ID). Both the partition and primary lookup are HMACs, never clear IDs.
  Future<List<String>> getKeysInScope(String scope) => _keys(scope: scope);

  Future<List<String>> _keys({String? scope}) => collection.locked(() async {
    final result = <String>{};
    if (!_cleared) {
      final keysStore = BoxCollection._keyStore(name);
      final scopeHash = scope == null
          ? null
          : await collection._scopeHash(keysStore, scope);
      JSAny? after;
      while (true) {
        final store = collection._db
            .transaction(keysStore.toJS, 'readonly')
            .objectStore(keysStore);
        final range = scopeHash != null
            ? IDBKeyRange.only(scopeHash.toJS)
            : after == null
            ? null
            : IDBKeyRange.lowerBound(after, true);
        // A room query reads only that room's small key records. Global
        // enumeration is paged and never loads/decrypts message values.
        final raw = scopeHash == null
            ? await Future.wait([
                _result(store.getAllKeys(range, 512)),
                _result(store.getAll(range, 512)),
              ])
            : await Future.wait([
                _result(store.index('scope').getAllKeys(range)),
                _result(store.index('scope').getAll(range)),
              ]);
        final hiddenKeys = raw[0]?.dartify() as List? ?? [];
        final rows = raw[1]?.dartify() as List? ?? [];
        if (rows.isEmpty) break;
        // Bound both crypto concurrency and temporary plaintext. Serial Web
        // Crypto calls make large enumerations unnecessarily slow on phones.
        for (var offset = 0; offset < rows.length; offset += 16) {
          result.addAll(
            await Future.wait([
              for (var i = offset; i < rows.length && i < offset + 16; i++)
                () async {
                  final hidden = hiddenKeys[i] as String,
                      wrapper = rows[i] as Map;
                  final decoded =
                      await collection.vault.open(
                            keysStore,
                            hidden,
                            (wrapper['sealed'] as Object?).jsify(),
                          )
                          as Map;
                  final key = decoded['key'] as String;
                  if (await collection.vault.hash(name, key) != hidden ||
                      decoded['scope'] != wrapper['scope'] ||
                      await collection._scopeHash(
                            keysStore,
                            key.split('|').first,
                          ) !=
                          decoded['scope'] ||
                      (scope != null && key.split('|').first != scope)) {
                    throw StateError('Protected key index mismatch.');
                  }
                  return key;
                }(),
            ]),
          );
        }
        if (scopeHash != null) break;
        after = (hiddenKeys.last as Object?).jsify();
      }
    }
    for (final change in _changes.entries) {
      if (scope != null && change.key.split('|').first != scope) continue;
      if (change.value == null) {
        result.remove(change.key);
      } else {
        result.add(change.key);
      }
    }
    return result.toList();
  });
  Future<V?> get(String key, [IDBTransaction? ignored]) => collection.locked(
    () async {
      if (_changes.containsKey(key)) return _changes[key];
      if (_cache.containsKey(key)) return _remember(key, _cache[key]);
      if (_cleared) return null;
      final hidden = await collection.vault.hash(name, key);
      final raw = await _result(
        collection._db
            .transaction(name.toJS, 'readonly')
            .objectStore(name)
            .get(hidden.toJS),
      );
      if (raw == null) return _remember(key, null);
      final decoded = await collection.vault.open(name, hidden, raw) as Map;
      if (decoded['key'] != key) throw StateError('Protected lookup mismatch.');
      return _remember(key, _value(decoded['value']));
    },
  );
  Future<List<V?>> getAll(List<String> keys, [IDBTransaction? ignored]) =>
      Future.wait(keys.map((key) => get(key)));
  Future<void> put(String key, V value, [IDBTransaction? ignored]) =>
      collection.transaction(() async {
        collection._pending!.add(
          () async => collection._prepareKey(
            name,
            key,
            await collection.vault.hash(name, key),
          ),
        );
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
        _remember(key, value);
        _changes[key] = value;
      });
  Future<void> delete(String key, [IDBTransaction? ignored]) =>
      collection.transaction(() async {
        collection._pending!.add(
          () async => _Write(
            BoxCollection._keyStore(name),
            'delete',
            await collection.vault.hash(name, key),
          ),
        );
        collection._pending!.add(
          () async =>
              _Write(name, 'delete', await collection.vault.hash(name, key)),
        );
        _remember(key, null);
        _changes[key] = null;
      });
  Future<void> deleteAll(List<String> keys, [IDBTransaction? ignored]) =>
      collection.transaction(() async {
        for (final key in keys) {
          await delete(key);
        }
      });
  void clearQuickAccessCache() {
    _cache.clear();
    _cacheSizes.clear();
    _cacheBytes = 0;
  }

  Future<void> clear([IDBTransaction? ignored]) =>
      collection.transaction(() async {
        collection._pending!.add(() async => _Write(name, 'clear'));
        collection._pending!.add(
          () async => _Write(BoxCollection._keyStore(name), 'clear'),
        );
        clearQuickAccessCache();
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
