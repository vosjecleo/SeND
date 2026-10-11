import 'package:deltiecord/ui/plain_message_editor.dart';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/voice_control_island.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets(
    'screen sharing without peers explains why capture cannot start',
    (tester) async {
      final backend = FakeBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => toggleVoiceScreenSharing(context, backend),
              child: const Text('Share'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.text('No one is connected to you yet'), findsOneWidget);
    },
  );

  testWidgets('opens voice rooms without exposing a message composer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!voice:example.org',
          name: 'Lounge',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Lounge'));
    await tester.pump();

    expect(find.text('VOICE ROOMS'), findsOneWidget);
    expect(find.text('Nobody is connected'), findsOneWidget);
    expect(find.byType(PlainMessageEditor), findsNothing);
    expect(backend.conversationVisibilityStates.last, isFalse);
    await tester.tap(find.byTooltip('Open chat'));
    await tester.pumpAndSettle();
    expect(backend.conversationVisibilityStates.last, isTrue);
    expect(find.byKey(const ValueKey('mobile-composer-field')), findsOneWidget);
  });

  testWidgets('exposes connected MatrixRTC media controls', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentVoiceStatus = VoiceConnectionStatus.connected
      ..currentActiveVoiceId = '!voice:example.org'
      ..roomList = const [
        RoomSummary(
          id: '!voice:example.org',
          name: 'Lounge',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Lounge'));
    await tester.pump();

    expect(find.text('Mute'), findsNothing);
    expect(find.byTooltip('Disconnect'), findsOneWidget);
    expect(find.byTooltip('Voice options'), findsOneWidget);
    await tester.tap(find.byTooltip('Voice options'));
    await tester.pumpAndSettle();
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Deafen'), findsOneWidget);
    expect(find.text('Camera on'), findsOneWidget);
    expect(find.text('Share screen'), findsOneWidget);
    expect(find.text('Share desktop audio'), findsOneWidget);
    await tester.tap(find.text('Deafen'));
    await tester.pump();
    expect(backend.deafened, isTrue);
  });

  testWidgets('shows RTC reconnect and a camera-off participant fallback', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentVoiceStatus = VoiceConnectionStatus.reconnecting
      ..currentActiveVoiceId = '!voice:example.org'
      ..cameraEnabled = true
      ..roomList = const [
        RoomSummary(
          id: '!voice:example.org',
          name: 'Lounge',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
          voiceParticipants: [
            VoiceParticipantSummary(
              userId: '@alice:example.org',
              displayName: 'Alice',
            ),
          ],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Lounge'));
    await tester.pump();

    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.text('Alice · camera off'), findsOneWidget);
  });

  testWidgets('Android keeps an RTC island while browsing another room', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentActiveVoiceId = '!voice:test'
      ..currentVoiceStatus = VoiceConnectionStatus.connected
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
        RoomSummary(
          id: '!voice:test',
          name: 'Voice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-call-island')), findsOneWidget);
  });
}
