import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/voice_room_view.dart';
import 'package:deltiecord/ui/mobile/mobile_voice_view.dart';
import 'package:deltiecord/ui/mobile/mobile_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'voice channel opens text without leaving the call: mobile=$mobile',
      (tester) async {
        tester.view.physicalSize = mobile
            ? const Size(390, 844)
            : const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..currentSpaceId = '!space:test'
          ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Space')]
          ..currentActiveVoiceId = '!voice:test'
          ..currentVoiceStatus = VoiceConnectionStatus.connected
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
            platformOverride: mobile
                ? TargetPlatform.android
                : TargetPlatform.linux,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Voice channel'));
        await tester.pumpAndSettle();
        expect(
          find.byType(mobile ? MobileVoiceView : VoiceRoomView),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Open chat'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileTimelineView), findsOneWidget);
        expect(backend.activeVoiceRoomId, '!voice:test');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
