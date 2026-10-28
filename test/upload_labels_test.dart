import 'package:deltiecord/services/upload_labels.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'labels persist across reopen, contain no content, and assets cannot be downgraded',
    () async {
      final sent = <List<Map<String, Object?>>>[];
      final first = UploadLabels('@a:test', (rows) async => sent.add(rows));
      await first.open();
      await first.add('mine', 'images', 'asset');
      await first.add('mine', 'images', 'upload');
      final reopened = UploadLabels('@a:test', (rows) async => sent.add(rows));
      await reopened.open();
      await reopened.flush();
      expect(sent.single, [
        {'media_id': 'mine', 'kind': 'images', 'source': 'asset'},
      ]);
      expect(
        sent.single.single.keys,
        unorderedEquals(['media_id', 'kind', 'source']),
      );
      final cleared = UploadLabels(
        '@a:test',
        (rows) async => fail('Already synchronized'),
      );
      await cleared.open();
      await cleared.flush();
    },
  );
  test(
    'failed synchronization is retained and an explicit retry can bypass backoff',
    () async {
      var failPost = true, posted = 0;
      final queue = UploadLabels('@a:test', (rows) async {
        posted++;
        if (failPost) throw StateError('offline');
      });
      await queue.open();
      await queue.add('mine', 'gifs', 'klipy');
      await queue.flush();
      expect(queue.warning, isNotNull);
      await queue.flush();
      expect(posted, 1);
      failPost = false;
      await queue.flush(force: true);
      expect(posted, 2);
      expect(queue.warning, isNull);
    },
  );
  test('one account cannot post another account’s pending labels', () async {
    final a = UploadLabels('@a:test', (_) async => fail('Not flushing a'));
    await a.open();
    await a.add('private-reference', 'videos', 'upload');
    final b = UploadLabels('@b:test', (_) async => fail('Wrong account queue'));
    await b.open();
    await b.flush();
  });
}
