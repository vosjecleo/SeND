import 'package:deltiecord/services/dm_call_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'DM/group call history survives a different participant ending the call',
    () async {
      final records = <Map<String, Object?>>[],
          cache = <String, Map<String, Object?>>{};
      final transactions = <String>{};
      var time = DateTime(2026, 10, 28, 12);
      DmCallHistory recorder(String identity) => DmCallHistory(
        identity: identity,
        now: () => time,
        read: (_) async => records.reversed.toList(),
        load: (_) async => cache[identity],
        save: (_, record) async {
          cache[identity] = record;
        },
        publish: (_, content, transaction) async {
          if (transactions.add('$identity:$transaction')) {
            records.add(
              Map<String, Object?>.from(content[callHistoryKey] as Map),
            );
          }
        },
      );
      final starter = recorder('@alice:test:ONE'),
          peer = recorder('@bob:test:TWO');
      await starter.joined('room', starting: true);
      await peer.joined('room', starting: false);
      await peer.joined('room', starting: false); // Rejoin is not another call.
      expect(records.length, 1);
      time = time.add(const Duration(minutes: 3, seconds: 4));
      await starter.left('room', empty: false, elected: true);
      expect(records.length, 1);
      await peer.left('room', empty: true, elected: true);
      expect(records.length, 2);
      expect(records.last['id'], records.first['id']);
      expect(records.last['duration_ms'], 184000);
      await peer.left('room', empty: true, elected: true);
      expect(records.length, 2);
      time = time.add(const Duration(hours: 1));
      await peer.joined('room', starting: true);
      expect(records.length, 3);
      expect(records.last['id'], isNot(records.first['id']));
    },
  );
}
