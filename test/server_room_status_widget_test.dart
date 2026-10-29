import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/space_administration.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/room_access_dialog.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _AccessBackend extends FakeBackend {
  _AccessBackend(this.channel);
  final bool channel;
  @override
  bool canMarkRoomDirect(String roomId) => !channel;
  @override
  Future<RoomAccessSettings> getRoomAccessSettings(String roomId) async =>
      RoomAccessSettings(
        roomId: roomId,
        joinRule: 'invite',
        historyVisibility: 'shared',
        discoverable: false,
        canEditAccess: false,
        canEditHistory: false,
        canEditPolicy: false,
        roomVersion: '11',
      );
}

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'stale channel models do not show a personal status, mobile=$mobile',
      (tester) async {
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = const [
            RoomSummary(
              id: '!channel:test',
              name: 'Server channel',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: true,
              isDirect: true,
              directUserId: '@peer:test',
              presence: UserPresence.online,
              statusMessage: 'Wrong channel status',
            ),
            RoomSummary(
              id: '!dm:test',
              name: 'Actual DM',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
              isDirect: true,
              directUserId: '@friend:test',
              presence: UserPresence.online,
              statusMessage: 'Actual DM status',
            ),
          ];
        expect(
          ActivityStatus.hasContent(backend, backend.roomList.first),
          false,
        );
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
        }
        await tester.pumpAndSettle();
        expect(find.text('Wrong channel status'), findsNothing);
        expect(find.text('Actual DM status'), findsOneWidget);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final channel in [false, true]) {
    testWidgets(
      'direct-message switch is only offered outside server channels, channel=$channel',
      (tester) async {
        final backend = _AccessBackend(channel);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showRoomAccessDialog(context, backend, '!room:test'),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.text('Treat as direct message'),
          channel ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
