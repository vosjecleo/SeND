import 'dart:async';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'support/backend_browser_fixture_stub.dart'
    if (dart.library.js_interop) 'support/backend_browser_fixture_web.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  Future<void> transaction(Future<void> Function() action) => action();
}

class _BackupKeys extends Fake implements KeyManager {
  final started = Completer<void>();
  final gate = Completer<bool>();
  final restored = <(String, String)>[];
  void Function()? restore;
  @override
  Future<Null> loadInboundGroupSession(String roomId, String sessionId) async =>
      null;
  @override
  Future<void> loadSingleKey(String roomId, String sessionId) async {
    restored.add((roomId, sessionId));
    restore?.call();
  }

  @override
  bool get enabled => true;
  @override
  Future<bool> isCached() {
    if (!started.isCompleted) started.complete();
    return gate.future;
  }
}

class _Encryption extends Fake implements Encryption {
  _Encryption(this.keys);
  final _BackupKeys keys;
  Future<Event> Function(Event)? decrypt;
  @override
  KeyManager get keyManager => keys;
  @override
  bool get enabled => false;
  @override
  Future<void> dispose() async {}
  @override
  Future<Event> decryptRoomEvent(
    Event event, {
    bool store = false,
    EventUpdateType updateType = EventUpdateType.timeline,
  }) async => decrypt == null ? event : await decrypt!(event);
}

class _Client extends Client {
  _Client({this.crypto}) : super('reply-preview-tests', database: _Database());
  final Encryption? crypto;
  final marked = <String>[];
  @override
  Future<void> setReadMarker(
    String roomId, {
    String? mFullyRead,
    String? mRead,
    String? mReadPrivate,
  }) async {
    if (mFullyRead != null) marked.add(mFullyRead);
  }

  @override
  Encryption? get encryption => crypto;
  @override
  String get userID => '@me:test';
}

class _Room extends Room {
  _Room(Client client, {super.id = '!reply:test'}) : super(client: client) {
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
  bool encryptedForTest = false;
  @override
  bool get encrypted => encryptedForTest || super.encrypted;
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
    onUpdate: onUpdate,
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
  Future<void> deliver(_Client client, _Room room, Event event) async {
    client.onTimelineEvent.add(event);
    // Give the pre-admission SDK callback time to finish. The sync callback
    // must independently resolve quotes and acknowledge the newly admitted row.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'arrival-test',
        rooms: RoomsUpdate(
          join: {
            room.id: JoinedRoomUpdate(
              timeline: TimelineUpdate(
                limited: false,
                events: [MatrixEvent.fromJson(event.toJson())],
              ),
            ),
          },
        ),
      ),
    );
  }

  test(
    'new synced replies resolve and acknowledge without another event',
    () async {
      final client = _Client();
      final room = _Room(client);
      room.events.add(room.event(r'$original', 'Cached original'));
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.selectRoom(room.id);
      backend.setConversationVisible(true);
      backend.setConversationAtPresent(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await deliver(
        client,
        room,
        room.event(r'$new', 'New reply', reply: r'$original'),
      );
      await settleReply(
        () => backend.messages.any(
          (m) => m.id == r'$new' && m.reply?.body == 'Cached original',
        ),
      );
      expect(
        backend.messages.firstWhere((m) => m.id == r'$new').reply?.body,
        'Cached original',
      );
      await settleReply(() => client.marked.contains(r'$new'));
      expect(client.marked, contains(r'$new'));
    },
  );

  test(
    'a slow old original cannot block a newly arrived cached quote',
    () async {
      final client = _Client();
      final room = _Room(client);
      final gate = Completer<Event?>();
      room.events.addAll([
        room.event(r'$old-reply', 'Old reply', reply: r'$remote'),
        room.event(r'$original', 'Cached original'),
      ]);
      room.lookup = (_) => gate.future;
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(() {
        backend.dispose();
        if (!gate.isCompleted) gate.complete(null);
      });
      await backend.selectRoom(room.id);
      await deliver(
        client,
        room,
        room.event(r'$new', 'New reply', reply: r'$original'),
      );
      await settleReply(
        () => backend.messages.any(
          (m) => m.id == r'$new' && m.reply?.body == 'Cached original',
        ),
      );
      expect(gate.isCompleted, false);
      expect(
        backend.messages.firstWhere((m) => m.id == r'$new').reply?.body,
        'Cached original',
      );
    },
  );
  test(
    'own replies resolve on admission and receipt-only sync publishes readers',
    () async {
      final client = _Client();
      final room = _Room(client);
      room.events.add(room.event(r'$original', 'Cached original'));
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.selectRoom(room.id);
      final own = Event.fromJson({
        ...room.event(r'$own', 'Own reply', reply: r'$original').toJson(),
        'sender': '@me:test',
      }, room);
      await deliver(client, room, own);
      await settleReply(
        () => backend.messages.any(
          (m) => m.id == r'$own' && m.reply?.body == 'Cached original',
        ),
      );
      final sent = backend.messages.firstWhere((m) => m.id == r'$own');
      expect(sent.own, true);
      expect(sent.reply?.body, 'Cached original');
      expect(sent.readBy, isEmpty);
      var published = false;
      backend.addListener(() {
        published = backend.messages
            .firstWhere((m) => m.id == r'$own')
            .readBy
            .any((reader) => reader.userId == '@friend:test');
      });
      // The SDK has applied a real receipt delta; the sync contains no new rows.
      room.receiptState.global.otherUsers['@friend:test'] =
          LatestReceiptStateData(r'$own', 123);
      client.onSync.add(SyncUpdate(nextBatch: 'receipt-only'));
      await settleReply(() => published);
      expect(published, true);
    },
  );
  testWidgets('automatic reply retries are bounded and stop on disposal', (
    tester,
  ) async {
    final client = _Client();
    final room = _Room(client);
    room.events.add(room.event(r'$reply', 'Reply', reply: r'$missing'));
    var lookups = 0;
    var available = false;
    room.lookup = (_) async {
      lookups++;
      return available
          ? room.event(r'$missing', 'Recovered after resume')
          : null;
    };
    client.rooms = [room];
    final backend = MatrixBackend(client: client);
    await backend.selectRoom(room.id);
    await tester.pump();
    final initial = lookups;
    expect(initial, greaterThan(0));
    for (final seconds in [1, 3, 10]) {
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
    }
    expect(lookups, initial + 3);
    await tester.pump(const Duration(minutes: 1));
    expect(lookups, initial + 3);
    available = true;
    backend.setApplicationForeground(false);
    backend.setApplicationForeground(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(backend.messages.single.reply?.body, 'Recovered after resume');
    expect(lookups, initial + 4);
    backend.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(lookups, initial + 4);
  });
  test(
    'transient lookup failure retries and publishes without a new message',
    () async {
      final client = _Client();
      final room = _Room(client);
      room.events.add(room.event(r'$reply', 'Reply', reply: r'$remote'));
      var lookups = 0;
      room.lookup = (_) async => ++lookups == 1
          ? null
          : room.event(r'$remote', 'Recovered without sending');
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      final published = Completer<void>();
      backend.addListener(() {
        if (!published.isCompleted &&
            backend.messages.any(
              (m) => m.reply?.body == 'Recovered without sending',
            )) {
          published.complete();
        }
      });
      await backend.selectRoom(room.id);
      await published.future.timeout(const Duration(seconds: 5));
      expect(lookups, 2);
      expect(backend.messages.length, 1);
    },
  );
  test(
    'a key for an out-of-window original refreshes the visible quote',
    () async {
      final crypto = _Encryption(_BackupKeys());
      var ready = false;
      final client = _Client(crypto: crypto);
      final room = _Room(client);
      room.events.add(room.event(r'$reply', 'Reply', reply: r'$remote'));
      final encrypted = Event.fromJson({
        ...room
            .event(r'$remote', 'Encrypted', type: EventTypes.Encrypted)
            .toJson(),
        'content': {
          'algorithm': 'm.megolm.v1.aes-sha2',
          'session_id': 'remote-session',
          'ciphertext': 'synthetic',
        },
      }, room);
      var lookups = 0, decryptions = 0;
      room.lookup = (_) async {
        lookups++;
        return encrypted;
      };
      crypto.decrypt = (event) async {
        decryptions++;
        return ready
            ? room.event(r'$remote', 'Original after key arrival')
            : event;
      };
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      final published = Completer<void>();
      backend.addListener(() {
        if (!published.isCompleted &&
            backend.messages.any(
              (m) => m.reply?.body == 'Original after key arrival',
            )) {
          published.complete();
        }
      });
      await backend.selectRoom(room.id);
      await settleReply(() => decryptions > 0);
      expect(backend.messages.single.reply?.senderId, isNull);
      ready = true;
      room.onSessionKeyReceived.add('remote-session');
      await published.future.timeout(const Duration(milliseconds: 500));
      expect(lookups, 1, reason: 'The encrypted original was already cached.');
      expect(backend.messages.single.reply?.body, 'Original after key arrival');
    },
  );
  test(
    'out-of-window quote restores only its own missing backup session',
    () async {
      final keys = _BackupKeys()..gate.complete(true);
      final crypto = _Encryption(keys);
      var restored = false;
      keys.restore = () => restored = true;
      final client = _Client(crypto: crypto);
      final room = _Room(client);
      room.events.add(room.event(r'$reply', 'Reply', reply: r'$remote'));
      final original = Event.fromJson({
        'event_id': r'$remote',
        'sender': '@friend:test',
        'type': EventTypes.Encrypted,
        'origin_server_ts': 1,
        'content': {
          'algorithm': 'm.megolm.v1.aes-sha2',
          'session_id': 'missing-quote-session',
          'ciphertext': 'synthetic',
        },
      }, room);
      room.lookup = (_) async => original;
      crypto.decrypt = (event) async => restored
          ? room.event(r'$remote', 'Original recovered from backup')
          : event;
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.selectRoom(room.id);
      await settleReply(
        () =>
            backend.messages.single.reply?.body ==
            'Original recovered from backup',
      );
      expect(
        backend.messages.single.reply?.body,
        'Original recovered from backup',
      );
      expect(keys.restored, [(room.id, 'missing-quote-session')]);
    },
  );
  test(
    'room changes cancel retries and ignore late lookup completion',
    () async {
      final client = _Client();
      final first = _Room(client);
      final second = _Room(client, id: '!other:test');
      final gate = Completer<Event?>();
      first.events.add(
        first.event(r'$old-reply', 'Old reply', reply: r'$remote'),
      );
      first.lookup = (_) => gate.future;
      second.events.addAll([
        second.event(r'$old-reply', 'Other room', reply: r'$other-original'),
        second.event(r'$other-original', 'Other original'),
      ]);
      client.rooms = [first, second];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.selectRoom(first.id);
      await backend.selectRoom(second.id);
      await settleReply(
        () => backend.messages.any((m) => m.reply?.body == 'Other original'),
      );
      var staleQuotePublished = false;
      backend.addListener(() {
        staleQuotePublished |= backend.messages.any(
          (m) => m.reply?.body == 'Old original',
        );
      });
      gate.complete(first.event(r'$remote', 'Old original'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        backend.messages.singleWhere((m) => m.id == r'$old-reply').reply?.body,
        'Other original',
      );
      expect(staleQuotePublished, isFalse);
    },
  );
  test(
    'cached reply resolves and notifies while unrelated backup work is blocked',
    () async {
      final keys = _BackupKeys();
      final client = _Client(crypto: _Encryption(keys));
      final room = _Room(client)..encryptedForTest = true;
      room.events.addAll([
        room.event(r'$reply', 'Reply', reply: r'$original'),
        room.event(r'$original', 'Original already here'),
      ]);
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      var publishedResolved = false;
      backend.addListener(() {
        if (backend.messages.any(
          (m) => m.id == r'$reply' && m.reply?.body == 'Original already here',
        )) {
          publishedResolved = true;
        }
      });
      final opening = backend.selectRoom(room.id);
      await keys.started.future;
      try {
        await settleReply(() => publishedResolved);
        expect(publishedResolved, isTrue);
        expect(
          backend.messages.singleWhere((m) => m.id == r'$reply').reply?.body,
          'Original already here',
        );
      } finally {
        keys.gate.complete(false);
        await opening;
      }
    },
  );
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
