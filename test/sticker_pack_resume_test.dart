import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  List<Event> persistedStates = [];
  bool fail = false;
  @override
  Future<List<Event>> getUnimportantRoomEventStatesForRoom(
    List<String> types,
    Room room,
  ) async {
    if (fail) throw StateError('Temporary local read failure');
    return persistedStates;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cold subscribed packs hydrate before publishing and survive read failures',
    () async {
      final database = _Database();
      final client = Client('pack-resume-test', database: database)
        ..setUserId('@me:test');
      final room = Room(
        id: '!packs:test',
        client: client,
        membership: Membership.join,
      );
      client.rooms = [room];
      client.accountData['im.ponies.emote_rooms'] = BasicEvent(
        type: 'im.ponies.emote_rooms',
        content: {
          'rooms': {
            room.id: {'pack': <String, Object?>{}},
          },
        },
      );
      database.persistedStates = [
        Event.fromJson({
          'type': 'im.ponies.room_emotes',
          'state_key': 'pack',
          'event_id': r'$pack',
          'sender': '@me:test',
          'origin_server_ts': 1,
          'content': {
            'pack': {'display_name': 'Persisted pack'},
            'images': {
              'cat': {
                'url': 'mxc://test/cat',
                'usage': ['sticker'],
              },
            },
          },
        }, room),
      ];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.refreshStickerPacks();
      expect(backend.stickerPacks.single.name, 'Persisted pack');
      room.partial = true;
      database.fail = true;
      await backend.refreshStickerPacks();
      expect(backend.stickerPacks.single.name, 'Persisted pack');
      // Authoritative deletion must not retain a pack indefinitely.
      database.fail = false;
      database.persistedStates = [];
      room.states.remove('im.ponies.room_emotes');
      await backend.refreshStickerPacks();
      expect(backend.stickerPacks, isEmpty);
    },
  );
}
