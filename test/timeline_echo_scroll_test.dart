import 'dart:convert';
import 'dart:typed_data';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/matrix/timeline_segments.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide RoomSummary;
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

import 'support/fake_backend.dart';
import 'support/timeline_segment_fixture.dart';
import 'support/widget_helpers.dart';

class _EchoBackend extends FakeBackend {
  late final model = MatrixTimelineSegments(notifyListeners);
  late final MatrixTimelineSegment segment;
  late final List<Event> history;
  @override
  List<ChatMessage> get messages => [
    for (final event
        in (selectedRoom?.id == segment.timeline.room.id
            ? segment.events
            : history))
      ChatMessage(
        id: event.eventId,
        transactionId: event.transactionId,
        own: event.senderId == '@me:test',
        senderId: event.senderId,
        sender: event.senderId == '@me:test' ? 'Me' : 'Friend',
        body: event.content['msgtype'] == 'm.image' ? '' : event.body,
        timestamp: event.originServerTs,
        pending: event.status.isSending,
        failed: event.status.isError,
        attachment: event.content['msgtype'] != 'm.image'
            ? null
            : const ChatAttachment(
                kind: AttachmentKind.image,
                name: 'same.png',
                mimeType: 'image/png',
                encrypted: true,
                size: 68,
                width: 100,
                height: 100,
                spoiler: false,
              ),
      ),
  ];
  @override
  Future<Uint8List> downloadAttachment(
    String id, {
    bool thumbnail = false,
  }) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY1kAAAAASUVORK5CYII=',
  );
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }
}

Event _photo(
  Room room,
  String id,
  String transaction, {
  bool pending = false,
}) => Event.fromJson({
  'event_id': id,
  'sender': '@me:test',
  'type': EventTypes.Message,
  'origin_server_ts': 3000000,
  'status': (pending ? EventStatus.sending : EventStatus.synced).intValue,
  'unsigned': {'transaction_id': transaction},
  'content': {
    'msgtype': 'm.image',
    'body': 'same.png',
    'url': 'mxc://test/same-upload',
    'info': {'w': 100, 'h': 100},
  },
}, room);

void main() {
  for (final mobile in [false, true]) {
    for (final scrolledUp in [false, true]) {
      testWidgets(
        'self-forward collage reconciles and keeps scrolling: mobile=$mobile scrolledUp=$scrolledUp',
        (tester) async {
          final client = SegmentClient(SegmentDatabase());
          final room = SegmentRoom(client);
          client.rooms = [room];
          final backend = _EchoBackend()
            ..currentStatus = SessionStatus.signedIn;
          addTearDown(backend.dispose);
          backend.history = room.range(0, 60);
          backend.segment = backend.model.adopt(
            Timeline(
              room: room,
              chunk: TimelineChunk(
                events: [
                  for (var i = 2; i >= 0; i--)
                    _photo(room, '\$original-$i', 'original-$i'),
                  ...backend.history,
                ],
              ),
            ),
            isLive: true,
          );
          backend.roomList = [
            RoomSummary(
              id: room.id,
              name: 'Self chat',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
            ),
            const RoomSummary(
              id: '!other:test',
              name: 'Other chat',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
            ),
          ];
          if (mobile) {
            await pumpMobile(tester, backend);
          } else {
            tester.view.physicalSize = const Size(1280, 688);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(DeltiecordApp(backend: backend));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Self chat'));
          await tester.pumpAndSettle();
          final timeline = find.byKey(
            Key(mobile ? 'mobile-message-timeline' : 'message-timeline'),
          );
          ScrollPosition position() => tester
              .state<ScrollableState>(
                find
                    .descendant(of: timeline, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          if (scrolledUp) {
            await tester.drag(timeline, const Offset(0, 400));
            await tester.pumpAndSettle();
          }
          for (var i = 0; i < 3; i++) {
            final tx = 'forward-$i';
            backend.model.appendRows(backend.segment, [
              _photo(room, tx, tx, pending: true),
            ], Direction.f);
            backend.notifyListeners();
            await tester.pump();
            final shared = backend.segment.events.firstWhere(
              (e) => e.status.isSynced,
            );
            final ack = _photo(room, '\$forwarded-$i', tx);
            backend.segment.timeline.events
              ..removeWhere((e) => e.eventId == tx)
              ..insert(0, ack);
            client.onSync.add(
              SyncUpdate(
                nextBatch: 'ack-$i',
                rooms: RoomsUpdate(
                  join: {
                    room.id: JoinedRoomUpdate(
                      timeline: TimelineUpdate(
                        limited: false,
                        events: [
                          shared,
                          ack,
                        ].map((e) => MatrixEvent.fromJson(e.toJson())).toList(),
                      ),
                    ),
                  },
                ),
              ),
            );
            await tester.pump();
            await tester.pumpAndSettle();
            expect(
              backend.messages.where((m) => m.transactionId == tx),
              hasLength(1),
            );
            expect(
              backend.messages.map((m) => m.timelineKey).toSet(),
              hasLength(backend.messages.length),
            );
            expect(tester.takeException(), isNull);
          }
          expect(backend.segment.events, hasLength(66));
          final before = position().pixels;
          await tester.drag(timeline, const Offset(0, 200));
          await tester.pumpAndSettle();
          expect(position().pixels, greaterThan(before));
          await backend.selectRoom('!other:test');
          await tester.pumpAndSettle();
          await tester.drag(timeline, const Offset(0, 200));
          await tester.pumpAndSettle();
          expect(position().pixels, greaterThan(0));
          await backend.selectRoom(room.id);
          await tester.pumpAndSettle();
          await tester.drag(timeline, const Offset(0, 200));
          await tester.pumpAndSettle();
          expect(position().pixels, greaterThan(0));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
