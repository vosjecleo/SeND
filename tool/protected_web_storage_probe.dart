import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:deltiecord/matrix/web_database/encrypted_box.dart';
import 'package:deltiecord/matrix/web_database/matrix_database.dart';

@JS('sendProtectedProbe')
external set _probe(JSFunction value);
@JS('sendProtectedProbeRead')
external set _readProbe(JSFunction value);
@JS('sendProtectedImportFailureProbe')
external set _importFailureProbe(JSFunction value);
@JS('sendProtectedIndexUpgradeProbe')
external set _indexUpgradeProbe(JSFunction value);
@JS('sendProtectedMixedMarkerProbe')
external set _mixedMarkerProbe(JSFunction value);
void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<JSAny?> run() async {
  var collection = await BoxCollection.open('send-vault-probe', {
    'values',
    'other',
  }, version: 11);
  var box = collection.openBox<Map>('values');
  check(
    (await box.get('!room:test'))?['body'] == 'legacy secret',
    'legacy migration',
  );
  await collection.transaction(() async {
    await box.put('nested', {'body': 'new secret'});
    await collection.transaction(() async => box.put('second', {'n': 2}));
    check((await box.getAllValues()).containsKey('nested'), 'read own writes');
  });
  final gate = Completer<void>(), started = Completer<void>();
  final transaction = collection.transaction(() async {
    await box.put('isolated', {'body': 'transaction'});
    started.complete();
    await gate.future;
    throw StateError('rollback fixture');
  });
  final failed = transaction.then((_) => false, onError: (Object _) => true);
  await started.future;
  final external = box.put('outside', {'body': 'independent'});
  gate.complete();
  check(await failed, 'rollback failure');
  await external;
  check(await box.get('isolated') == null, 'rolled back row');
  check(
    (await box.get('outside'))?['body'] == 'independent',
    'independent write survives',
  );
  await collection.transaction(() async {
    await box.clear();
    await box.put('kept', {'body': 'after clear'});
    check((await box.getAllValues()).length == 1, 'clear read own writes');
  });
  await collection.close();
  collection = await BoxCollection.open('send-vault-probe', {
    'values',
    'other',
  }, version: 11);
  box = collection.openBox<Map>('values');
  check((await box.get('kept'))?['body'] == 'after clear', 'reopen');
  for (var i = 0; i < 300; i++) {
    await box.put('!room${i % 3}:test|$i', {'body': 'x' * 5000});
  }
  check(
    box.cachedRecordCount <= Box.maximumCachedRecords &&
        box.cachedBytes <= Box.maximumCachedBytes,
    'bounded plaintext cache',
  );
  box.clearQuickAccessCache();
  check(
    (await box.getKeysInScope('!room1:test')).length == 100,
    'room-scoped index',
  );
  check(
    box.cachedRecordCount == 0,
    'key enumeration did not cache message values',
  );
  await collection.transaction(() async {
    await box.delete('!room1:test|1');
    await box.put('!room1:test|new', {'body': 'pending'});
    final keys = await box.getKeysInScope('!room1:test');
    check(
      !keys.contains('!room1:test|1') && keys.contains('!room1:test|new'),
      'index read own writes',
    );
    // Pending changes must remain readable even after cache eviction.
    check(
      (await box.get('!room1:test|new'))?['body'] == 'pending',
      'pending cache consistency',
    );
  });
  // Leave the original fixture for subsequent corruption/missing-key tests.
  await collection.transaction(() async {
    await box.clear();
    await box.put('kept', {'body': 'after clear'});
    check((await box.getAllKeys()).length == 1, 'index clear/read own writes');
  });
  await collection.close();
  final sdk = await ProtectedWebMatrixDatabase.init('send-sdk-probe');
  check(
    (await sdk.getClient('test'))?['token'] == 'legacy-token-fixture',
    'SDK session migration',
  );
  await sdk.cacheCustomObject('profile', {'bio': 'private biography'});
  check(
    (await sdk.getCustomCacheObject('profile'))?.content['bio'] ==
        'private biography',
    'SDK cache',
  );
  await sdk.insertClient(
    'test',
    'https://example.org',
    'next-token-fixture',
    null,
    null,
    '@a:test',
    'DEVICE',
    'Device',
    'sync-cursor',
    'olm-fixture',
    null,
  );
  check(
    (await sdk.getClient('test'))?['token'] == 'next-token-fixture',
    'SDK client writes',
  );
  final snapshot = jsonDecode(await sdk.exportDump()) as Map<String, dynamic>;
  check(snapshot.length == 23, 'every persistent collection exported');
  // Populate all collections, including messages, both session types, queued
  // session backups, device keys, receipts, profiles and timeline fragments.
  for (final entry in snapshot.entries) {
    if (entry.key == 'box_client') continue;
    entry.value['fixture'] = switch (entry.key) {
      'box_seen_device_ids' ||
      'box_seen_device_keys' ||
      'box_inbound_group_sessions_upload_queue' => 'private-fixture',
      'box_user_device_keys_outdated' => true,
      'box_timeline_fragments' => ['event-fixture'],
      _ => {'fixture': 'private persistent state'},
    };
  }
  final original = jsonEncode(snapshot);
  check(await sdk.importDump(original), 'complete snapshot import');
  check(await sdk.exportDump() == original, 'complete round trip');
  check(await sdk.exportDump() == original, 'export is non-destructive');
  for (final invalid in [
    'not json',
    '{}',
    original.replaceFirst('true', '42'),
  ]) {
    check(!await sdk.importDump(invalid), 'invalid import rejected');
    check(await sdk.exportDump() == original, 'invalid import retained data');
  }
  final legacy = Map<String, dynamic>.from(snapshot)
    ..remove('box_read_receipts')
    ..remove('box_user_profiles');
  check(await sdk.importDump(jsonEncode(legacy)), 'legacy dump accepted');
  check(await sdk.exportDump() == original, 'legacy omitted stores retained');
  final wrongAccount = jsonDecode(jsonEncode(legacy)) as Map<String, dynamic>;
  wrongAccount['box_client']['user_id'] = '@other:test';
  check(
    !await sdk.importDump(jsonEncode(wrongAccount)),
    'legacy cross-account import rejected',
  );
  check(
    await sdk.exportDump() == original,
    'cross-account rejection retained data',
  );
  await sdk.close();
  final reopened = await ProtectedWebMatrixDatabase.init('send-sdk-probe');
  check(
    await reopened.exportDump() == original,
    'restored state survives reopen',
  );
  await reopened.close();
  return true.toJS;
}

void main() {
  _mixedMarkerProbe = (() => () async {
    BoxCollection? collection;
    try {
      collection = await BoxCollection.open('send-mixed-marker-probe', {
        'values',
      }, version: 11);
      return true.toJS;
    } catch (_) {
      return false.toJS;
    } finally {
      await collection?.close();
    }
  }().toJS).toJS;
  _indexUpgradeProbe = (() => () async {
    BoxCollection? collection;
    try {
      collection = await BoxCollection.open('send-index-upgrade-probe', {
        'values',
      }, version: 11);
      final box = collection.openBox<Map>('values');
      check(
        (await box.getKeysInScope('!legacy:test')).length == 2,
        'encrypted index upgrade',
      );
      check(
        (await box.get('!legacy:test|one'))?['body'] == 'retained secret',
        'upgrade preserves values',
      );
      return true.toJS;
    } catch (_) {
      return false.toJS;
    } finally {
      await collection?.close();
    }
  }().toJS).toJS;
  _importFailureProbe = (() => () async {
    final sdk = await ProtectedWebMatrixDatabase.init('send-sdk-probe');
    try {
      final before = await sdk.exportDump();
      check(!await sdk.importDump(before), 'aborted IDB import rejected');
      check(
        await sdk.exportDump() == before,
        'aborted IDB import retained data',
      );
      return true.toJS;
    } finally {
      await sdk.close();
    }
  }().toJS).toJS;
  _readProbe = (() => () async {
    BoxCollection? collection;
    try {
      collection = await BoxCollection.open('send-vault-probe', {
        'values',
        'other',
      }, version: 11);
      final value = await collection.openBox<Map>('values').get('kept');
      return (value?['body'] == 'after clear').toJS;
    } catch (_) {
      return false.toJS;
    } finally {
      await collection?.close();
    }
  }().toJS).toJS;
  _probe =
      (() => run().catchError((Object error) => error.toString().toJS).toJS)
          .toJS;
}
