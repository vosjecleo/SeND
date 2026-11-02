import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

class _Database implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends Client {
  _Client() : super('reply-mentions', database: _Database());
  @override
  String get userID => '@me:test';
}

class _Room extends Room {
  _Room(Client client) : super(id: '!room:test', client: client);
  final events = <Event>[];
  Map<String, dynamic>? sent;
  Event? sentReply;
  @override
  Future<Timeline> getTimeline({
    void Function(int)? onChange,
    void Function(int)? onRemove,
    void Function(int)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async => Timeline(
    room: this,
    chunk: TimelineChunk(events: events),
  );
  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    sent = content;
    sentReply = inReplyTo;
    return r'$sent';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final target in ['@me:test', '@friend:test']) {
    for (final sender in ['@friend:test', '@me:test']) {
      test(
        'edited reply keeps recipient highlight, sender=$sender target=$target',
        () async {
          final client = _Client();
          final room = _Room(client);
          for (final user in ['@me:test', '@friend:test']) {
            room.setState(
              Event.fromJson({
                'event_id': '\$member-$user',
                'sender': user,
                'state_key': user,
                'type': EventTypes.RoomMember,
                'origin_server_ts': 1,
                'content': {'membership': 'join', 'displayname': user},
              }, room),
            );
          }
          Event event(
            String id,
            String sender,
            Map<String, Object?> content,
            int ts,
          ) => Event.fromJson({
            'event_id': id,
            'sender': sender,
            'type': EventTypes.Message,
            'origin_server_ts': ts,
            'content': {'msgtype': 'm.text', ...content},
          }, room);
          room.events.addAll([
            event(r'$edit', sender, {
              'body': '* changed',
              'm.new_content': {'msgtype': 'm.text', 'body': 'changed'},
              'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$reply'},
            }, 3000),
            event(r'$reply', sender, {
              'body': 'original reply',
              'm.mentions': {
                'user_ids': [target],
              },
              'm.relates_to': {
                'm.in_reply_to': {'event_id': r'$target'},
              },
            }, 2000),
            event(r'$target', target, {'body': 'target'}, 1000),
          ]);
          client.rooms = [room];
          final backend = MatrixBackend(client: client);
          await backend.selectRoom(room.id);
          final reply = backend.messages.singleWhere((m) => m.id == r'$reply');
          expect(reply.body, 'changed');
          expect(reply.pingedCurrentUser, target == '@me:test');
          expect(reply.hasVisualMention, false);
          if (sender == '@me:test') {
            await backend.sendMessage(
              'new reply',
              roomId: room.id,
              replyToMessageId: r'$target',
            );
            expect(room.sentReply?.eventId, r'$target');
            expect(
              (room.sent!['m.mentions'] as Map)['user_ids'],
              contains(target),
            );
            await backend.sendMessage(
              'edited again',
              roomId: room.id,
              editMessageId: r'$reply',
            );
            expect(room.sentReply?.eventId, r'$target');
            expect(
              (room.sent!['m.mentions'] as Map)['user_ids'],
              contains(target),
            );
          }
          backend.dispose();
        },
      );
    }
  }
}
