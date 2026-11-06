import 'package:deltiecord/services/notification_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
}

void main() {
  test(
    'sticker notifications have a useful label instead of generic activity',
    () {
      final client = Client('label-test', database: _Database());
      addTearDown(client.dispose);
      final room = Room(id: '!test:test', client: client);
      for (final record in [
        (
          'm.sticker',
          {'body': 'A custom sticker', 'url': 'mxc://test/sticker'},
          'Sticker',
        ),
        ('m.room.message', {'msgtype': 'm.text', 'body': 'Hello'}, 'Hello'),
        ('m.room.member', {'membership': 'join'}, 'New room activity'),
      ]) {
        final event = Event.fromJson({
          'type': record.$1,
          'content': record.$2,
          'event_id': r'$test',
          'sender': '@sender:test',
          'origin_server_ts': 1,
        }, room);
        expect(notificationEventBody(event), record.$3);
      }
    },
  );
}
