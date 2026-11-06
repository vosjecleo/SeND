import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/services/message_forwarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:deltiecord/models/media_gallery.dart';
import 'package:deltiecord/models/saved_gif_reference.dart';
import 'package:deltiecord/services/gif_identity.dart';

class _Database implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends Client {
  _Client() : super('forwarding', database: _Database());
  @override
  String get userID => '@me:test';
}

class _Room extends Room {
  _Room(Client client, String id) : super(id: id, client: client);
  final events = <String, Event>{};
  final sent = <Map<String, dynamic>>[];
  int? failAfter;
  bool locked = false, encryptedForTest = false;
  String? expectedReply;
  @override
  bool get encrypted => encryptedForTest;
  @override
  bool canSendEvent(String type) => !locked;
  @override
  Future<Event?> getEventById(String id) async => events[id];
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
    if (failAfter == sent.length) throw StateError('Connection lost');
    expect(type, EventTypes.Message);
    expect(inReplyTo?.eventId, expectedReply);
    expect(editEventId, isNull);
    expect(threadRootEventId, isNull);
    sent.add(content);
    return '\$sent-${sent.length}';
  }

  void add(
    String id,
    String body, {
    bool media = false,
    bool redacted = false,
  }) {
    events[id] = Event.fromJson({
      'event_id': id,
      'sender': '@peer:test',
      'type': EventTypes.Message,
      'origin_server_ts': 1000,
      if (redacted)
        'unsigned': {
          'redacted_because': {'type': 'm.room.redaction'},
        },
      'content': {
        'msgtype': media ? 'm.image' : 'm.text',
        'body': body,
        if (media) 'url': 'mxc://test/$id',
      },
    }, this);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Client client;
  late _Room source, destination;
  late MatrixBackend backend;
  setUp(() {
    client = _Client();
    source = _Room(client, '!source:test');
    destination = _Room(client, '!destination:test');
    client.rooms = [source, destination];
    backend = MatrixBackend(client: client);
    source.add('a', 'First caption', media: true);
    source.add('b', 'Second photo', media: true);
    source.add('c', 'Text');
  });
  tearDown(() => backend.dispose());
  Future<void> forward(List<String> ids, {bool confirm = true}) =>
      backend.forwardMessages(
        sourceRoomId: source.id,
        eventIds: ids,
        destinationRoomId: destination.id,
        allowUnencrypted: confirm,
      );
  test(
    'saved GIF reuses encrypted file, strips caption and old mentions, and replies in destination',
    () async {
      final file = <String, dynamic>{
        'url': 'mxc://test/already-uploaded',
        'key': {'k': 'encrypted-file-key'},
        'iv': 'original-iv',
        'hashes': {'sha256': 'original-hash'},
        'v': 'v2',
      };
      source.events[r'$gif'] = Event.fromJson({
        'event_id': r'$gif',
        'sender': '@peer:test',
        'type': EventTypes.Message,
        'origin_server_ts': 1000,
        'content': {
          'msgtype': MessageTypes.Image,
          'body': 'Private caption',
          'format': 'org.matrix.custom.html',
          'formatted_body': '<b>Private caption</b>',
          'info': {'mimetype': 'image/gif'},
          'net.deltiecord.gif_source': 'https://static.klipy.com/reuse.gif',
          'file': file,
          'm.mentions': {
            'user_ids': ['@old:test'],
          },
        },
      }, source);
      source.lastEvent = source.events[r'$gif'];
      final reusable = backend.uploadedGifForSource(
        Uri.parse('https://static.klipy.com/reuse.gif'),
      )!;
      expect(reusable.roomId, source.id);
      expect(reusable.eventId, r'$gif');
      destination.add(r'$reply', 'Destination message');
      destination.expectedReply = r'$reply';
      await backend.sendSavedGif(
        const SavedGifReference(roomId: '!source:test', eventId: r'$gif'),
        roomId: destination.id,
        replyToMessageId: r'$reply',
        allowUnencrypted: true,
      );
      final sent = destination.sent.single;
      expect(sent['file'], file);
      expect(sent['body'], 'animation.gif');
      expect(sent[gifIdentityContentKey], gifIdentityFor(source.id, r'$gif'));
      expect(sent.containsKey('formatted_body'), false);
      expect(sent.containsKey('url'), false);
      expect(
        (sent['m.mentions'] as Map)['user_ids'],
        isNot(contains('@old:test')),
      );
      expect(source.sent, isEmpty);
    },
  );
  test('saved GIF cannot silently send to unencrypted destination', () async {
    await expectLater(
      backend.sendSavedGif(
        const SavedGifReference(roomId: '!source:test', eventId: r'$gif'),
        roomId: destination.id,
      ),
      throwsA(isA<ForwardingFailure>()),
    );
    expect(destination.sent, isEmpty);
  });
  test(
    'collage forwards all media in caller order, once, without upload',
    () async {
      await forward(['b', 'a', 'b']);
      expect(destination.sent.map((e) => e['body']), [
        'Second photo',
        'First caption',
      ]);
      expect(destination.sent.map((e) => e['url']), [
        'mxc://test/b',
        'mxc://test/a',
      ]);
      expect(source.sent, isEmpty);
    },
  );
  test(
    'text forwarding does not depend on the currently selected room',
    () async {
      await forward(['c']);
      expect(destination.sent.single['body'], 'Text');
      expect(destination.sent.single['m.mentions'], isEmpty);
    },
  );
  test(
    'forwarded media gets a fresh gallery for each forwarding operation',
    () async {
      await forward(['a', 'b']);
      final first = [
        for (final event in destination.sent)
          MediaGalleryMembership.fromJson(
            event[MediaGalleryMembership.contentKey],
          )!,
      ];
      expect(first.map((m) => m.index), [0, 1]);
      expect(first.map((m) => m.id).toSet(), hasLength(1));
      await forward(['a', 'b']);
      expect(
        MediaGalleryMembership.fromJson(
          destination.sent.last[MediaGalleryMembership.contentKey],
        )!.id,
        isNot(first.first.id),
      );
      expect(destination.sent.map((m) => m['url']), [
        'mxc://test/a',
        'mxc://test/b',
        'mxc://test/a',
        'mxc://test/b',
      ]);
    },
  );
  test('unencrypted destination requires explicit confirmation', () async {
    await expectLater(
      forward(['c'], confirm: false),
      throwsA(isA<ForwardingFailure>()),
    );
    expect(destination.sent, isEmpty);
  });
  test(
    'large legacy galleries forward every file in bounded fresh groups',
    () async {
      final ids = [
        for (var i = 0; i <= MediaGalleryMembership.maximumItems; i++) 'old-$i',
      ];
      for (final id in ids) {
        source.add(id, id, media: true);
      }
      await forward(ids);
      expect(destination.sent, hasLength(ids.length));
      expect(
        destination.sent.map((e) => e['url']),
        ids.map((id) => 'mxc://test/$id'),
      );
      final memberships = destination.sent
          .map(
            (e) => MediaGalleryMembership.fromJson(
              e[MediaGalleryMembership.contentKey],
            )!,
          )
          .toList();
      expect(
        memberships
            .take(MediaGalleryMembership.maximumItems)
            .map((g) => g.id)
            .toSet(),
        hasLength(1),
      );
      expect(memberships.last.id, isNot(memberships.first.id));
      expect(memberships.last.index, 0);
      expect(memberships.last.count, 1);
    },
  );
  test(
    'encrypted destination never falls back to plaintext without crypto',
    () async {
      destination.encryptedForTest = true;
      await expectLater(forward(['c']), throwsA(isA<ForwardingFailure>()));
      expect(destination.sent, isEmpty);
    },
  );
  test('missing collage member aborts before any member is sent', () async {
    await expectLater(
      forward(['a', 'missing']),
      throwsA(isA<ForwardingFailure>().having((e) => e.sent, 'sent', 0)),
    );
    expect(destination.sent, isEmpty);
  });
  test(
    'partial send failure reports count and never silently repeats a member',
    () async {
      destination.failAfter = 1;
      await expectLater(
        forward(['a', 'b', 'c']),
        throwsA(
          isA<ForwardingFailure>()
              .having((e) => e.sent, 'sent', 1)
              .having((e) => e.total, 'total', 3),
        ),
      );
      expect(destination.sent, hasLength(1));
    },
  );
  test('read-only or left rooms cannot receive forwarded messages', () async {
    destination.locked = true;
    await expectLater(forward(['c']), throwsA(isA<ForwardingFailure>()));
    destination.locked = false;
    destination.membership = Membership.leave;
    await expectLater(forward(['c']), throwsA(isA<ForwardingFailure>()));
    expect(destination.sent, isEmpty);
  });
  test('deleted source event cannot be forwarded', () async {
    source.add('deleted', 'old text', redacted: true);
    await expectLater(forward(['deleted']), throwsA(isA<ForwardingFailure>()));
    expect(destination.sent, isEmpty);
  });
}
