import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/forward_message_dialog.dart';
import 'package:deltiecord/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _Backend extends FakeBackend {
  final forwards = <List<String>>[];
  String? source, destination;
  bool? allowed;
  @override
  String? roomIdForMessage(String id) => 'source';
  @override
  Future<void> forwardMessages({
    required String sourceRoomId,
    required List<String> eventIds,
    required String destinationRoomId,
    bool allowUnencrypted = false,
  }) async {
    source = sourceRoomId;
    destination = destinationRoomId;
    allowed = allowUnencrypted;
    forwards.add(List.of(eventIds));
  }
}

void main() {
  for (final mobile in [false, true]) {
    for (final collage in [false, true]) {
      testWidgets(
        'forward through actual message menu: mobile=$mobile collage=$collage',
        (tester) async {
          const source = RoomSummary(
            id: 'source',
            name: 'Source chat',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
            encrypted: true,
          );
          const destination = RoomSummary(
            id: 'target',
            name: 'Destination',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
            encrypted: true,
          );
          final backend = _Backend()
            ..currentStatus = SessionStatus.signedIn
            ..roomList = [source, destination]
            ..messageList = [
              for (final index in (collage ? [3, 2, 1] : [1]))
                ChatMessage(
                  id: 'event-$index',
                  sender: 'Sender',
                  senderId: '@peer:test',
                  body: collage ? '' : 'Forward this text',
                  timestamp: DateTime(2026, 11, 2, 12, index),
                  pending: false,
                  attachment: collage
                      ? ChatAttachment(
                          kind: AttachmentKind.image,
                          name: 'image-$index.png',
                          mimeType: 'image/png',
                          size: 68,
                          encrypted: true,
                          width: 100,
                          height: 100,
                          spoiler: true,
                        )
                      : null,
                ),
            ];
          if (mobile) {
            await pumpMobile(tester, backend);
          } else {
            tester.view.physicalSize = const Size(1400, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(DeltiecordApp(backend: backend));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text(source.name));
          await tester.pumpAndSettle();
          final avatar = find.byKey(
            ValueKey(
              '${mobile ? 'mobile-message' : 'message'}-avatar-event-${collage ? 3 : 1}',
            ),
          );
          if (mobile) {
            await tester.longPress(avatar);
          } else {
            await revealMessageActions(tester, avatar);
          }
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('message-action-forward')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Forward to'), findsOneWidget);
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(ListTile, 'Destination'),
            ),
          );
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Forward'));
          await tester.pumpAndSettle();
          expect(backend.forwards, [
            collage ? ['event-1', 'event-2', 'event-3'] : ['event-1'],
          ]);
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final encrypted in [false, true]) {
    testWidgets('forward picker confirms destination, encrypted=$encrypted', (
      tester,
    ) async {
      final backend = _Backend()
        ..roomList = [
          RoomSummary(
            id: 'target',
            name: 'Destination',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
            encrypted: encrypted,
          ),
          const RoomSummary(
            id: 'other',
            name: 'Other chat',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          ),
        ];
      final messages = [
        for (final id in ['first', 'second', 'third'])
          ChatMessage(
            id: id,
            sender: 'Sender',
            body: 'Message',
            timestamp: DateTime(2026),
            pending: false,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showForwardMessageDialog(context, backend, messages),
                child: const Text('Open forwarding'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open forwarding'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Forward'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'destination');
      await tester.pump();
      expect(find.text('Other chat'), findsNothing);
      await tester.tap(find.text('Destination'));
      await tester.pump();
      expect(backend.forwards, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Forward'));
      await tester.pumpAndSettle();
      if (!encrypted) {
        expect(find.text('Forward without encryption?'), findsOneWidget);
        expect(backend.forwards, isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, 'Forward'));
        await tester.pumpAndSettle();
      }
      expect(backend.forwards, [
        ['first', 'second', 'third'],
      ]);
      expect(backend.source, 'source');
      expect(backend.destination, 'target');
      expect(backend.allowed, !encrypted);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('cancel never sends a message', (tester) async {
    final backend = _Backend();
    final message = ChatMessage(
      id: 'event',
      sender: 'Sender',
      body: 'Text',
      timestamp: DateTime(2026),
      pending: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showForwardMessageDialog(context, backend, [message]),
              child: const Text('Open forwarding'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open forwarding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.forwards, isEmpty);
  });
}
