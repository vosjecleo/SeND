import 'package:deltiecord/matrix/timeline_segments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'support/timeline_segment_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('server-ordered overlapping ranges merge without dropping rows', () {
    final client = SegmentClient(SegmentDatabase());
    final room = SegmentRoom(client);
    final union = mergeOverlappingEvents(
      room.range(-80, 110),
      room.range(-100, 30),
    );
    expect(
      union?.map((e) => e.eventId).toList(),
      room.range(-100, 130).map((e) => e.eventId).toList(),
    );
  });
  test('limited ranges join only on proven overlap', () async {
    final client = SegmentClient(SegmentDatabase());
    final room = SegmentRoom(client);
    final model = MatrixTimelineSegments(() {});
    addTearDown(model.dispose);
    model.adopt(await room.getTimeline(), isLive: true);
    await room.limited(-100);
    final active = model.active!;
    model.appendRows(active, room.range(-80, 80), Direction.f);
    model.reconcile(active);
    expect(model.ranges.length, 1);
    expect(active.events.length, 130);
    expect(active.live, true);
  });
  test('disconnected and contradictory ranges never get a guessed merge', () {
    final room = SegmentRoom(SegmentClient(SegmentDatabase()));
    expect(
      mergeOverlappingEvents(room.range(0, 30), room.range(100, 30)),
      isNull,
    );
    expect(
      mergeOverlappingEvents(
        room.range(0, 30),
        room.range(0, 30).reversed.toList(),
      ),
      isNull,
    );
  });
  test('shared local echoes cannot prove continuity between server ranges', () {
    final room = SegmentRoom(SegmentClient(SegmentDatabase()));
    final pending = Event.fromJson({
      ...room.event(-1000).toJson(),
      'status': EventStatus.sending.intValue,
    }, room);
    expect(
      mergeOverlappingEvents(
        [pending, ...room.range(0, 30)],
        [pending, ...room.range(100, 30)],
      ),
      isNull,
    );
  });
  test(
    'a forward EOF cannot claim Present if sync already advanced to a disconnected head',
    () async {
      final room = SegmentRoom(SegmentClient(SegmentDatabase()));
      final model = MatrixTimelineSegments(() {});
      addTearDown(model.dispose);
      final original = model.adopt(await room.getTimeline(), isLive: true);
      await room.limited(-100);
      model.reachedLiveEnd(original);
      expect(original.live, false);
      expect(original.newer, same(model.live));
      expect(original.timeline.allowNewEvent, false);
    },
  );
  test(
    'limited sync retains every loaded row, including histories larger than the old cap',
    () async {
      final room = SegmentRoom(SegmentClient(SegmentDatabase()));
      final model = MatrixTimelineSegments(() {});
      addTearDown(model.dispose);
      final timeline = await room.getTimeline();
      timeline.events.addAll(room.range(30, 470));
      final original = model.adopt(timeline, isLive: true);
      await room.limited(-100);
      expect(model.active, same(original));
      expect(
        original.events.map((e) => e.eventId).toList(),
        room.range(0, 500).map((e) => e.eventId).toList(),
      );
      expect(model.ranges.length, 2);
      expect(model.live!.events.length, 30);
    },
  );
}
