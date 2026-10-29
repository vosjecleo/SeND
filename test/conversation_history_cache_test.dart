import 'dart:async';
import 'package:deltiecord/services/conversation_history_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bounded snapshots survive reopen, prune oldest conversations',
    () async {
      Map<String, Object?>? disk;
      ConversationHistoryCache open() => ConversationHistoryCache(
        owner: Object(),
        read: () async => disk,
        write: (value) async => disk = value,
      );
      final cache = open();
      for (var i = 0; i < 20; i++) {
        await cache.put(
          'thread$i',
          List.generate(100, (n) => {'event_id': '$n'}),
        );
      }
      await cache.flush();
      cache.dispose();
      final restored = open();
      expect(await restored.get('thread0'), isEmpty);
      expect(
        (await restored.get('thread19')).length,
        ConversationHistoryCache.maximumEvents,
      );
      expect(
        (disk!['entries'] as Map).length,
        ConversationHistoryCache.maximumConversations,
      );
      restored.dispose();
    },
  );
  test(
    'byte cap and disposal prevent unbounded writes and late restore',
    () async {
      var writes = 0;
      final load = Completer<Map<String, Object?>?>();
      final cache = ConversationHistoryCache(
        owner: Object(),
        read: () => load.future,
        write: (_) async {
          writes++;
        },
      );
      final reading = cache.get('thread');
      cache.dispose();
      load.complete({'version': 1, 'entries': {}});
      expect(await reading, isEmpty);
      await cache.put('thread', [
        {'body': 'ignored'},
      ]);
      await cache.flush();
      expect(writes, 0);
      Map<String, Object?>? disk;
      final bounded = ConversationHistoryCache(
        owner: Object(),
        read: () async => null,
        write: (v) async => disk = v,
      );
      await bounded.put('oversized', [
        {'body': 'x' * (ConversationHistoryCache.maximumBytes + 1)},
      ]);
      await bounded.flush();
      expect((disk!['entries'] as Map), isEmpty);
      bounded.dispose();
    },
  );
}
