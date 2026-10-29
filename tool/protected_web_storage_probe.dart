import 'dart:async';
import 'dart:js_interop';
import 'package:deltiecord/matrix/web_database/encrypted_box.dart';
import 'package:deltiecord/matrix/web_database/matrix_database.dart';

@JS('sendProtectedProbe')
external set _probe(JSFunction value);
@JS('sendProtectedProbeRead')
external set _readProbe(JSFunction value);
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
  await sdk.close();
  return true.toJS;
}

void main() {
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
