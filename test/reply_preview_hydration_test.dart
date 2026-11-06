import 'dart:async';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'support/backend_browser_fixture_stub.dart'
    if (dart.library.js_interop) 'support/backend_browser_fixture_web.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
}

class _Client extends Client {
  _Client() : super('reply-preview-tests', database: _Database());
  @override
  String get userID => '@me:test';
}

class _Room extends Room {
  _Room(Client client) : super(id: '!reply:test', client: client) {
    for (final user in ['@friend:test', '@me:test']) {
      setState(
        Event.fromJson({
          'type': EventTypes.RoomMember,
          'state_key': user,
          'sender': user,
          'event_id': '\$member-$user',
          'origin_server_ts': 1,
          'content': {'membership': 'join', 'displayname': user},
        }, this),
      );
    }
  }
  final events = <Event>[];
  Future<Event?> Function(String)? lookup;
  @override
  Future<Event?> getEventById(String id) async => lookup?.call(id);
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
    chunk: TimelineChunk(events: List.of(events)),
  );
  Event event(
    String id,
    String body, {
    String type = EventTypes.Message,
    String? reply,
  }) => Event.fromJson({
    'event_id': id,
    'sender': '@friend:test',
    'type': type,
    'origin_server_ts': events.length + 1,
    'content': {
      'msgtype': 'm.text',
      'body': body,
      if (type == EventTypes.Sticker) ...{
        'url': 'mxc://test/sticker',
        'info': {'mimetype': 'image/png', 'w': 128, 'h': 128},
      },
      if (reply != null)
        'm.relates_to': {
          'm.in_reply_to': {'event_id': reply},
        },
    },
  }, this);
}

Future<void> settleReply(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    addTearDown(installBackendBrowserFixture());
  });
  test('replies sharing a remote target coalesce their lookup', () async {
    final client = _Client();
    final room = _Room(client);
    final gate = Completer<Event?>();
    room.events.addAll([
      room.event(r'$one', 'One', reply: r'$remote'),
      room.event(r'$two', 'Two', reply: r'$remote'),
    ]);
    var lookups = 0;
    room.lookup = (_) {
      lookups++;
      return gate.future;
    };
    client.rooms = [room];
    final backend = MatrixBackend(client: client);
    addTearDown(backend.dispose);
    await backend.selectRoom(room.id);
    await settleReply(() => lookups > 0);
    expect(lookups, 1);
    gate.complete(room.event(r'$remote', 'Shared original'));
    await settleReply(
      () =>
          backend.messages.every((message) => message.reply?.senderId != null),
    );
    expect(
      backend.messages.every(
        (message) => message.reply?.body == 'Shared original',
      ),
      true,
    );
  });
  test(
    'sticker targets and sticker replies retain their quote previews',
    () async {
      final client = _Client();
      final room = _Room(client);
      room.events.addAll([
        room.event(r'$text', 'Original text'),
        room.event(r'$sticker', 'Original sticker', type: EventTypes.Sticker),
        room.event(r'$reply-to-sticker', 'Reply', reply: r'$sticker'),
        room.event(
          r'$sticker-reply',
          'Reply sticker',
          type: EventTypes.Sticker,
          reply: r'$text',
        ),
      ]);
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.selectRoom(room.id);
      await settleReply(
        () =>
            backend.messages
                .where((m) => m.id == r'$reply-to-sticker')
                .first
                .reply
                ?.senderId !=
            null,
      );
      expect(
        backend.messages
            .singleWhere((m) => m.id == r'$reply-to-sticker')
            .reply
            ?.body,
        'Original sticker',
      );
      expect(
        backend.messages
            .singleWhere((m) => m.id == r'$sticker-reply')
            .reply
            ?.body,
        'Original text',
      );
    },
  );
  test(
    'a failed target cannot hide another quote, and unknown senders are never invented',
    () async {
      final client = _Client();
      final room = _Room(client);
      room.events.addAll([
        room.event(r'$bad-reply', 'Bad lookup', reply: r'$missing'),
        room.event(r'$good-reply', 'Good lookup', reply: r'$remote'),
      ]);
      room.lookup = (id) async {
        if (id == r'$missing') throw StateError('Temporary lookup failure');
        return room.event(id, 'Remote original');
      };
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.selectRoom(room.id);
      await settleReply(
        () =>
            backend.messages
                .singleWhere((m) => m.id == r'$good-reply')
                .reply
                ?.senderId !=
            null,
      );
      final failed = backend.messages
          .singleWhere((m) => m.id == r'$bad-reply')
          .reply!;
      expect(failed.eventId, r'$missing');
      expect(failed.senderId, isNull);
      expect(failed.body, 'View original message');
      expect(
        backend.messages.singleWhere((m) => m.id == r'$good-reply').reply?.body,
        'Remote original',
      );
    },
  );
  test(
    'the quote relation is visible before an out-of-window original arrives',
    () async {
      final client = _Client();
      final room = _Room(client);
      final gate = Completer<Event?>();
      room.events.add(room.event(r'$reply', 'Reply', reply: r'$remote'));
      room.lookup = (_) => gate.future;
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.selectRoom(room.id);
      expect(backend.messages.single.reply?.eventId, r'$remote');
      expect(backend.messages.single.reply?.senderId, isNull);
      gate.complete(room.event(r'$remote', 'Late original'));
      await settleReply(() => backend.messages.single.reply?.senderId != null);
      expect(backend.messages.single.reply?.body, 'Late original');
    },
  );
}
