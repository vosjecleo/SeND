import 'dart:convert';
import 'dart:js_interop';
import 'package:deltiecord/matrix/web_database/encrypted_box.dart';

@JS('sendStorageBenchmark')
external set _benchmark(JSFunction value);

Future<JSString> run(int count) async {
  final collection = await BoxCollection.open('send-storage-benchmark', {
    'events',
  });
  final box = collection.openBox<Map>('events');
  final payload = 'x' * 2048;
  final timer = Stopwatch()..start();
  for (var offset = 0; offset < count; offset += 100) {
    await collection.transaction(() async {
      for (var i = offset; i < offset + 100 && i < count; i++) {
        await box.put('!room${i % 100}:test|event$i', {'body': payload});
      }
    });
  }
  final writeMs = timer.elapsedMilliseconds;
  box.clearQuickAccessCache();
  timer.reset();
  final keys = await box.getAllKeys();
  final keysMs = timer.elapsedMilliseconds;
  timer.reset();
  final roomKeys = await box.getKeysInScope('!room0:test');
  final roomKeysMs = timer.elapsedMilliseconds;
  if (roomKeys.length != (count / 100).ceil()) {
    throw StateError('Room keys missing.');
  }
  if (keys.length != count) throw StateError('Benchmark rows missing.');
  await collection.close();
  return jsonEncode({
    'rows': count,
    'writeMs': writeMs,
    'keysMs': keysMs,
    'roomKeysMs': roomKeysMs,
    'cachedRecords': box.cachedRecordCount,
    'cachedBytes': box.cachedBytes,
  }).toJS;
}

void main() {
  _benchmark = ((JSNumber count) => run(count.toDartInt).toJS).toJS;
}
