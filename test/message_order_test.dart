import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/message_order.dart';

ChatMessage event(String id, int time, {bool pending = false}) => ChatMessage(
  id: id,
  sender: 'Test',
  senderId: '@test:example.org',
  body: id,
  timestamp: DateTime.fromMillisecondsSinceEpoch(time),
  pending: pending,
  own: true,
);

void main() {
  test('server timestamps and stable tie breakers ignore arrival order', () {
    final events = [event('a', 20), event('z', 20), event('c', 10)];
    expect((events.toList()..sort(compareTimelineMessages)).map((e) => e.id), [
      'z',
      'a',
      'c',
    ]);
    expect(
      (events.reversed.toList()..sort(compareTimelineMessages)).map(
        (e) => e.id,
      ),
      ['z', 'a', 'c'],
    );
  });
  test(
    'local echoes remain provisional even with an incorrect local clock',
    () {
      final events = [event('sent', 100), event('pending', 1, pending: true)];
      expect((events..sort(compareTimelineMessages)).first.id, 'pending');
    },
  );
}
