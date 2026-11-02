import 'dart:async';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'support/timeline_segment_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SegmentDatabase db;
  late SegmentClient client;
  late SegmentRoom room;
  late MatrixBackend backend;
  setUp(() {
    db = SegmentDatabase();
    client = SegmentClient(db);
    room = SegmentRoom(client);
    client.rooms = [room];
    backend = MatrixBackend(client: client);
  });
  tearDown(() => backend.dispose());
  Set<String> ids() => backend.messages.map((m) => m.id).toSet();

  test('a stale DB page cannot advance the fresh Present cursor', () async {
    final delayed = Completer<List<Event>>();
    db.read = (_, start, count) => db.starts.length == 1
        ? delayed.future
        : Future.value(room.range(start, count));
    await backend.selectRoom(room.id);
    final old = backend.loadMoreHistory();
    while (db.starts.isEmpty) {
      await settleSegmentStreams();
    }
    await backend.jumpToPresent();
    delayed.complete(room.range(30, 30));
    await old;
    await backend.loadMoreHistory();
    expect(db.starts, [30, 30]);
    expect(ids(), containsAll([r'$event30', r'$event59']));
  });

  test('pending echoes do not consume positions in stored history', () async {
    room.pending = 2;
    db.read = (_, start, count) async => room.range(start, count);
    await backend.selectRoom(room.id);
    await backend.loadMoreHistory();
    expect(db.starts.first, 30);
    expect(ids(), containsAll([r'$event30', r'$event31']));
  });

  test(
    'limited sync retains old rows and cannot splice a delayed page into the live range',
    () async {
      final delayed = Completer<GetRoomEventsResponse>();
      client.page = (_, _) => delayed.future;
      await backend.selectRoom(room.id);
      final oldId = backend.timelineSegmentId;
      final old = backend.loadMoreHistory();
      while (client.requests.isEmpty) {
        await settleSegmentStreams();
      }
      await room.limited(-100);
      expect(backend.timelineSegmentId, oldId);
      expect(backend.timelineHasGap, true);
      expect(ids(), room.range(0, 30).map((e) => e.eventId).toSet());
      delayed.complete(
        GetRoomEventsResponse(
          start: 'older-edge',
          end: 'old-next',
          chunk: room.wireRange(30, 30),
        ),
      );
      await old;
      expect(ids(), room.range(0, 30).map((e) => e.eventId).toSet());
      expect(backend.atTimelinePresent, false);
      expect(backend.historyLoading, false);
      await backend.jumpToPresent();
      expect(ids(), room.range(-100, 30).map((e) => e.eventId).toSet());
      expect(backend.atTimelinePresent, true);
      await backend.jumpToEvent(r'$event5');
      expect(backend.timelineSegmentId, oldId);
      expect(ids(), containsAll([r'$event0', r'$event29']));
    },
  );

  test(
    'a gap closes only after forward pagination overlaps the live range, preserving all rows and segment identity',
    () async {
      await backend.selectRoom(room.id);
      final original = backend.timelineSegmentId;
      await room.limited(-100);
      room.contextHead = -5;
      client.page = (direction, from) async {
        expect(direction, Direction.f);
        expect(from, 'context-newer');
        return GetRoomEventsResponse(
          start: from ?? '',
          end: 'more-future',
          chunk: room.wireRange(-80, 75).reversed.toList(),
        );
      };
      await backend.loadMoreFuture();
      expect(backend.timelineSegmentId, original);
      expect(backend.timelineHasGap, false);
      expect(backend.atTimelinePresent, true);
      expect(ids(), room.range(-100, 130).map((e) => e.eventId).toSet());
      expect(backend.messages.length, 130);
      expect(backend.historyLoading, false);
    },
  );

  test(
    'Present preserves overlapping loaded history instead of trimming to its initial page',
    () async {
      db.read = (_, start, count) async => room.range(start, count);
      await backend.selectRoom(room.id);
      await backend.loadMoreHistory();
      final loaded = ids();
      expect(loaded.length, 60);
      await backend.jumpToPresent();
      expect(ids(), containsAll(loaded));
      expect(backend.messages.length, 60);
    },
  );
  test(
    'retained older messages still receive edits, reactions and redactions without absorbing new rows',
    () async {
      await backend.selectRoom(room.id);
      final original = backend.timelineSegmentId;
      await room.limited(-100);
      client.onTimelineEvent.add(
        Event.fromJson({
          'type': EventTypes.Message,
          'event_id': r'$edit',
          'sender': '@friend:test',
          'origin_server_ts': 3000000,
          'content': {
            'msgtype': 'm.text',
            'body': '* changed',
            'm.new_content': {
              'msgtype': 'm.text',
              'body': 'Changed old message',
            },
            'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$event0'},
          },
        }, room),
      );
      await settleSegmentStreams();
      expect(
        backend.messages.singleWhere((m) => m.id == r'$event0').body,
        'Changed old message',
      );
      client.onTimelineEvent.add(
        Event.fromJson({
          'type': EventTypes.Reaction,
          'event_id': r'$reaction',
          'sender': '@friend:test',
          'origin_server_ts': 3000001,
          'content': {
            'm.relates_to': {
              'rel_type': 'm.annotation',
              'event_id': r'$event0',
              'key': '👍',
            },
          },
        }, room),
      );
      await settleSegmentStreams();
      expect(
        backend.messages.singleWhere((m) => m.id == r'$event0').reactions,
        hasLength(1),
      );
      for (final target in [r'$reaction', r'$edit', r'$event0']) {
        client.onTimelineEvent.add(
          Event.fromJson({
            'type': EventTypes.Redaction,
            'event_id': '\$redact-$target',
            'sender': '@friend:test',
            'origin_server_ts': 3000002,
            'redacts': target,
            'content': {'redacts': target},
          }, room),
        );
        await settleSegmentStreams();
        if (target == r'$edit') {
          expect(
            backend.messages.singleWhere((m) => m.id == r'$event0').body,
            'Synthetic 0',
          );
        }
      }
      final removed = backend.messages.singleWhere((m) => m.id == r'$event0');
      expect(removed.redacted, true);
      expect(removed.body, isNot(contains('Changed old message')));
      expect(removed.reactions, isEmpty);
      expect(backend.timelineSegmentId, original);
      expect(backend.messages.length, 30);
      expect(ids(), isNot(contains(r'$event-100')));
    },
  );
  test(
    'older paging after a gap anchors at the retained tail, not the new live token',
    () async {
      await backend.selectRoom(room.id);
      final original = backend.timelineSegmentId;
      await room.limited(-100);
      room.contextHead = 24;
      await backend.loadMoreHistory();
      expect(room.contextRequests, [r'$event29']);
      expect(backend.timelineSegmentId, original);
      expect(ids(), room.range(0, 54).map((e) => e.eventId).toSet());
      client.page = (direction, from) async {
        expect(direction, Direction.b);
        expect(from, 'context-older');
        return GetRoomEventsResponse(
          start: from!,
          end: 'older-next',
          chunk: room.wireRange(54, 30),
        );
      };
      await backend.loadMoreHistory();
      expect(ids(), room.range(0, 84).map((e) => e.eventId).toSet());
    },
  );
  test(
    'failed history requests release only their own range and can be retried',
    () async {
      db.read = (_, start, count) async => throw StateError('offline');
      await backend.selectRoom(room.id);
      final before = ids();
      await backend.loadMoreHistory();
      expect(backend.historyLoading, false);
      expect(ids(), before);
      db.read = (_, start, count) async => room.range(start, count);
      await backend.loadMoreHistory();
      expect(ids(), containsAll([r'$event30', r'$event59']));
    },
  );
}
