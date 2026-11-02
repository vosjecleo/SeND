import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
}

class _Client extends Client {
  _Client() : super('posting-permissions', database: _Database());
  @override
  String get userID => '@reader:test';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'posting follows room power levels, not whether the channel has readers',
    () {
      final client = _Client();
      final room = Room(id: '!announcements:test', client: client);
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      void powers(int level) => room.setState(
        Event.fromJson({
          'type': EventTypes.RoomPowerLevels,
          'state_key': '',
          'event_id': '\$power-$level',
          'sender': '@admin:test',
          'origin_server_ts': 1,
          'content': {
            'events_default': 50,
            'users': {'@reader:test': level},
          },
        }, room),
      );
      powers(0);
      expect(backend.canSendMessagesToRoom(room.id), false);
      powers(50);
      expect(backend.canSendMessagesToRoom(room.id), true);
      room.membership = Membership.leave;
      expect(backend.canSendMessagesToRoom(room.id), false);
      expect(backend.canSendMessagesToRoom('!missing:test'), false);
    },
  );
}
