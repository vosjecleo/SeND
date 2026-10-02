import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

class _ChannelBackend extends FakeBackend {
  bool editable = false;
  @override
  bool canChangeRoomState(String roomId, String eventType) =>
      editable && roomId == '!voice:test' && eventType == 'm.room.name';
}

void main() {
  for (final editable in [false, true]) {
    testWidgets(
      'mobile channel long-press respects room permissions: $editable',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = _ChannelBackend()
          ..editable = editable
          ..currentStatus = SessionStatus.signedIn
          ..currentSpaceId = '!space:test'
          ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Space')]
          ..roomList = const [
            RoomSummary(
              id: '!voice:test',
              name: 'Voice channel',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: true,
              presentation: RoomPresentation.voice,
            ),
          ];
        await tester.pumpWidget(
          DeltiecordApp(
            backend: backend,
            platformOverride: TargetPlatform.android,
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Voice channel'));
        await tester.pumpAndSettle();
        expect(find.text('Copy room link'), findsOneWidget);
        expect(
          find.text('Room settings'),
          editable ? findsOneWidget : findsNothing,
        );
        if (editable) {
          await tester.tap(find.text('Room settings'));
          await tester.pumpAndSettle();
          final fields = tester
              .widgetList<TextField>(find.byType(TextField))
              .toList();
          expect(
            fields.any(
              (field) =>
                  field.decoration?.labelText == 'Name' &&
                  field.enabled == true,
            ),
            isTrue,
          );
          expect(
            fields.any(
              (field) =>
                  field.decoration?.labelText == 'Topic' &&
                  field.enabled == false,
            ),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
