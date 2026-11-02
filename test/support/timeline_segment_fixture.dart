import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

class SegmentDatabase extends Fake implements MatrixSdkDatabase {
  final starts = <int>[];
  Future<List<Event>> Function(Room, int, int)? read;
  @override
  Future<void> close() async {}
  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    if (onlySending) return [];
    starts.add(start);
    return await read?.call(room, start, limit ?? 30) ?? [];
  }
}

class SegmentClient extends Client {
  SegmentClient(this.storage) : super('segment-tests', database: storage);
  final SegmentDatabase storage;
  final requests = <(Direction, String?)>[];
  Future<GetRoomEventsResponse> Function(Direction, String?)? page;
  @override
  String get userID => '@me:test';
  @override
  Future<GetRoomEventsResponse> getRoomEvents(
    String roomId,
    Direction dir, {
    String? from,
    String? to,
    int? limit,
    String? filter,
  }) async {
    requests.add((dir, from));
    return await page?.call(dir, from) ??
        GetRoomEventsResponse(chunk: [], start: from ?? '');
  }
}

class SegmentRoom extends Room {
  SegmentRoom(Client client) : super(id: '!segments:test', client: client) {
    setState(
      Event.fromJson({
        'type': EventTypes.RoomMember,
        'state_key': '@friend:test',
        'sender': '@friend:test',
        'event_id': r'$member',
        'origin_server_ts': 1,
        'content': {'membership': 'join', 'displayname': 'Friend'},
      }, this),
    );
  }
  int latestHead = 0;
  int? contextHead;
  int pending = 0;
  final contextRequests = <String>[];
  @override
  Future<TimelineChunk?> getEventContext(String eventId) async {
    contextRequests.add(eventId);
    final anchor = int.parse(eventId.replaceFirst(r'$event', ''));
    return TimelineChunk(
      events: range(contextHead ?? anchor - 5, 30),
      prevBatch: 'context-older',
      nextBatch: 'context-newer',
    );
  }

  final timelines = <Timeline>[];
  Event event(int i) => Event.fromJson({
    'type': EventTypes.Message,
    'sender': '@friend:test',
    'event_id': '\$event$i',
    'origin_server_ts': 2000000 - i * 1000,
    'content': {'msgtype': 'm.text', 'body': 'Synthetic $i'},
  }, this);
  List<Event> range(int start, int count) =>
      List.generate(count, (i) => event(start + i));
  List<MatrixEvent> wireRange(int start, int count) =>
      range(start, count).map((e) => MatrixEvent.fromJson(e.toJson())).toList();
  @override
  Future<Timeline> getTimeline({
    void Function(int)? onChange,
    void Function(int)? onRemove,
    void Function(int)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async {
    final historical = eventContextId != null;
    final local = List.generate(
      pending,
      (i) => Event.fromJson({
        ...event(-1000 - i).toJson(),
        'status': EventStatus.sending.intValue,
      }, this),
    );
    final timeline = Timeline(
      room: this,
      onUpdate: onUpdate,
      chunk: TimelineChunk(
        events: [
          if (!historical) ...local,
          ...range(historical ? contextHead ?? 300 : latestHead, 30),
        ],
        prevBatch: 'older-edge',
        nextBatch: historical ? 'context-newer' : '',
      ),
    );
    timelines.add(timeline);
    return timeline;
  }

  Future<void> limited(int head) async {
    latestHead = head;
    prev_batch = 'newer-edge';
    final incoming = range(head, 30);
    for (final event in incoming.reversed) {
      client.onTimelineEvent.add(event);
    }
    await settleSegmentStreams();
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'new-sync',
        rooms: RoomsUpdate(
          join: {
            id: JoinedRoomUpdate(
              timeline: TimelineUpdate(
                limited: true,
                prevBatch: prev_batch,
                events: incoming.reversed
                    .map((e) => MatrixEvent.fromJson(e.toJson()))
                    .toList(),
              ),
            ),
          },
        ),
      ),
    );
    await settleSegmentStreams();
  }
}

Future<void> settleSegmentStreams() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
