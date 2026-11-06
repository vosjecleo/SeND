import 'package:deltiecord/matrix/timeline_segments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

import 'support/timeline_segment_fixture.dart';

Event echo(
  Room room,
  String id, {
  String? transaction = 'forward-tx',
  EventStatus status = EventStatus.synced,
  String sender = '@me:test',
  bool redacted = false,
  bool encrypted = false,
}) => Event.fromJson({
  'event_id': id,
  'sender': sender,
  'status': status.intValue,
  'type': encrypted ? EventTypes.Encrypted : EventTypes.Message,
  'origin_server_ts': 3000000,
  'unsigned': {
    'transaction_id': ?transaction,
    if (redacted)
      'redacted_because': {
        'type': EventTypes.Redaction,
        'event_id': r'$redaction',
        'sender': '@me:test',
        'origin_server_ts': 3000001,
        'content': <String, dynamic>{},
      },
  },
  'content': encrypted
      ? {
          'algorithm': 'm.megolm.v1.aes-sha2',
          'ciphertext': 'synthetic',
          'session_id': 'synthetic',
          'sender_key': 'synthetic',
        }
      : {'msgtype': 'm.text', 'body': 'Forwarded content'},
}, room);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SegmentClient client;
  late SegmentRoom room;
  late MatrixTimelineSegments model;
  setUp(() {
    client = SegmentClient(SegmentDatabase());
    room = SegmentRoom(client);
    client.rooms = [room];
    model = MatrixTimelineSegments(() {});
  });
  tearDown(() => model.dispose());
  MatrixTimelineSegment adopt(List<Event> events, {bool live = true}) =>
      model.adopt(
        Timeline(
          room: room,
          chunk: TimelineChunk(events: List.of(events)),
        ),
        isLive: live,
      );

  for (final status in [EventStatus.error, EventStatus.sending]) {
    test(
      'overlapping sync replaces $status echo once, preserving all history',
      () async {
        final history = room.range(0, 500);
        final pending = echo(room, 'forward-tx', status: status);
        final ack = echo(room, r'$forwarded');
        final segment = adopt([pending, ...history]);
        segment.timeline.events
          ..clear()
          ..addAll([ack, ...history]);
        for (var i = 0; i < 3; i++) {
          client.onSync.add(
            SyncUpdate(
              nextBatch: 'ack-$i',
              rooms: RoomsUpdate(
                join: {
                  room.id: JoinedRoomUpdate(
                    timeline: TimelineUpdate(
                      limited: false,
                      events: [
                        history.first,
                        ack,
                      ].map((e) => MatrixEvent.fromJson(e.toJson())).toList(),
                    ),
                  ),
                },
              ),
            ),
          );
          await settleSegmentStreams();
          expect(segment.events.map((e) => e.eventId), [
            r'$forwarded',
            ...history.map((e) => e.eventId),
          ]);
          expect(
            segment.events.where((e) => e.transactionId == 'forward-tx'),
            hasLength(1),
          );
        }
      },
    );
  }
  test(
    'acknowledgement keeps server order rather than the old echo position',
    () {
      final history = room.range(0, 3);
      final pending = echo(room, 'forward-tx', status: EventStatus.sending);
      final ack = echo(room, r'$forwarded');
      final merged = mergeOverlappingEvents(
        [history[0], ack, ...history.skip(1)],
        [pending, ...history],
      );
      expect(merged!.map((e) => e.eventId), [
        history[0].eventId,
        ack.eventId,
        ...history.skip(1).map((e) => e.eventId),
      ]);
    },
  );
  test(
    'an echo without unsigned transaction metadata still reconciles by local ID',
    () {
      final segment = adopt([
        echo(
          room,
          'forward-tx',
          transaction: null,
          status: EventStatus.sending,
        ),
        ...room.range(0, 3),
      ]);
      segment.timeline.events
        ..clear()
        ..addAll([echo(room, r'$forwarded'), ...room.range(0, 3)]);
      model.refreshKnown(segment);
      expect(segment.events.map((e) => e.eventId), [
        r'$forwarded',
        ...room.range(0, 3).map((e) => e.eventId),
      ]);
    },
  );
  test('stale pending SDK state cannot resurrect an acknowledged row', () {
    final ack = echo(room, r'$forwarded');
    final segment = adopt([ack, ...room.range(0, 3)]);
    segment.timeline.events
      ..clear()
      ..addAll([
        echo(room, 'forward-tx', status: EventStatus.sending),
        ...room.range(0, 3),
      ]);
    model.refreshKnown(segment);
    expect(segment.events.first.eventId, ack.eventId);
    expect(
      segment.events.where((e) => e.transactionId == 'forward-tx'),
      hasLength(1),
    );
  });
  test(
    'sent POST response and synced copy share one event without downgrading',
    () {
      final synced = echo(room, r'$forwarded');
      final segment = adopt([
        synced,
        echo(room, r'$forwarded', status: EventStatus.sent),
      ]);
      expect(segment.events, hasLength(1));
      expect(segment.events.single.status, EventStatus.synced);
    },
  );
  test('different senders with the same transaction string stay distinct', () {
    final segment = adopt([
      echo(room, 'forward-tx', status: EventStatus.sending),
      echo(room, r'$other', sender: '@other:test'),
    ]);
    expect(segment.events.map((e) => e.eventId), ['forward-tx', r'$other']);
  });
  test(
    'distinct server events and distinct collage transactions are never discarded',
    () {
      final segment = adopt([
        echo(room, r'$one'),
        echo(room, r'$two'),
        echo(
          room,
          'another-local',
          transaction: 'second-tx',
          status: EventStatus.sending,
        ),
      ]);
      expect(segment.events.map((e) => e.eventId), [
        r'$one',
        r'$two',
        'another-local',
      ]);
    },
  );
  test('duplicate error/sending copies represent only one local request', () {
    final segment = adopt([
      echo(room, 'first-local', status: EventStatus.sending),
      echo(room, 'retry-local', status: EventStatus.error),
    ]);
    expect(segment.events, hasLength(1));
    expect(segment.events.single.status, EventStatus.error);
  });
  test('redaction and decrypted content survive stale duplicate copies', () {
    final redacted = echo(room, r'$removed', redacted: true);
    final decrypted = echo(room, r'$decrypted', transaction: 'decrypted');
    final segment = adopt([
      redacted,
      echo(room, r'$removed'),
      decrypted,
      echo(room, r'$decrypted', transaction: 'decrypted', encrypted: true),
    ]);
    expect(segment.events, hasLength(2));
    expect(segment.events.first.redacted, true);
    expect(segment.events.last.type, EventTypes.Message);
  });
  test('transaction alias alone never proves a gap is filled', () {
    final pending = echo(room, 'forward-tx', status: EventStatus.sending);
    final ack = echo(room, r'$forwarded');
    expect(
      mergeOverlappingEvents(
        [ack, ...room.range(0, 3)],
        [pending, ...room.range(100, 3)],
      ),
      isNull,
    );
  });
  test(
    'appending an acknowledgement removes its echo but no distinct events',
    () {
      final history = room.range(0, 20);
      final segment = adopt([
        echo(room, 'forward-tx', status: EventStatus.sending),
        ...history,
      ]);
      model.appendRows(segment, [echo(room, r'$forwarded')], Direction.f);
      expect(segment.events.map((e) => e.eventId), [
        r'$forwarded',
        ...history.map((e) => e.eventId),
      ]);
      expect(
        segment.timeline.events.map((e) => e.eventId),
        segment.events.map((e) => e.eventId),
      );
    },
  );
  test(
    'burst acknowledgements reconcile each collage transaction once',
    () async {
      final history = room.range(0, 200);
      final pending = [
        for (var i = 7; i >= 0; i--)
          echo(
            room,
            'local-$i',
            transaction: 'collage-$i',
            status: EventStatus.sending,
          ),
      ];
      final ack = [
        for (var i = 7; i >= 0; i--)
          echo(room, '\$collage-$i', transaction: 'collage-$i'),
      ];
      final segment = adopt([...pending, ...history]);
      segment.timeline.events
        ..clear()
        ..addAll([...ack, ...history]);
      client.onSync.add(
        SyncUpdate(
          nextBatch: 'collage',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  limited: false,
                  events: [...ack, history.first].reversed
                      .map((e) => MatrixEvent.fromJson(e.toJson()))
                      .toList(),
                ),
              ),
            },
          ),
        ),
      );
      await settleSegmentStreams();
      for (var pass = 0; pass < 5; pass++) {
        model.refreshKnown(segment);
        expect(segment.events.map((e) => e.eventId), [
          ...ack.map((e) => e.eventId),
          ...history.map((e) => e.eventId),
        ]);
        expect(segment.events.where((e) => !e.status.isSynced), isEmpty);
      }
    },
  );
  test('refresh does not insert unknown server rows into a retained range', () {
    final history = room.range(0, 5);
    final segment = adopt(history);
    segment.timeline.events.insert(0, room.event(-50));
    model.refreshKnown(segment);
    expect(segment.events.map((e) => e.eventId), history.map((e) => e.eventId));
  });
  test(
    'merge does not resurrect redacted or re-encrypt decrypted duplicates',
    () {
      final original = [
        echo(room, r'$removed', redacted: true),
        echo(room, r'$plain', transaction: 'plain'),
      ];
      final stale = [
        echo(room, r'$removed'),
        echo(room, r'$plain', transaction: 'plain', encrypted: true),
      ];
      final merged = mergeOverlappingEvents(stale, original)!;
      expect(merged.first.redacted, true);
      expect(merged.last.type, EventTypes.Message);
    },
  );
}
