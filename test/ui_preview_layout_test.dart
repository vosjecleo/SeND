import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/json_theme.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/mobile/mobile_widgets.dart';
import 'package:deltiecord/ui/mobile/mobile_voice_view.dart';
import 'package:deltiecord/ui/voice_room_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

const _room = RoomSummary(
  id: 'room',
  name: 'Preview chat',
  lastMessage: '',
  unreadCount: 0,
  usesChannelIcon: false,
  isDirect: true,
  directUserId: '@peer:test',
  presence: UserPresence.online,
  statusMessage: 'Making tea',
);

class _CallBackend extends FakeBackend {
  bool left = false;
  @override
  Future<void> setVoiceCameraEnabled(bool value) async {
    cameraEnabled = value;
    notifyListeners();
  }

  @override
  Future<void> leaveVoiceRoom() async {
    left = true;
  }
}

void main() {
  testWidgets('one-line jumbo emoji keeps its avatar centered too', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [_room]
      ..messageList = [
        ChatMessage(
          id: 'emoji',
          sender: 'Sender',
          senderId: '@sender:test',
          body: '👍',
          timestamp: DateTime(2026),
          pending: false,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Preview chat'));
    await tester.pumpAndSettle();
    final avatar = tester.getRect(
      find.byKey(const ValueKey('mobile-message-avatar-emoji')),
    );
    final sender = tester.getRect(find.text('Sender'));
    final body = tester.getRect(
      find.byKey(const ValueKey('mobile-message-body-emoji')),
    );
    expect(avatar.center.dy, closeTo((sender.top + body.bottom) / 2, 1));
    await tester.pumpWidget(const SizedBox());
  });
  for (final reply in [false, true]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'short formatted avatar centers against its entry: reply=$reply scale=$scale',
        (tester) async {
          final backend = FakeBackend()
            ..currentStatus = SessionStatus.signedIn
            ..currentPreferences = AppPreferences(fontScale: scale)
            ..roomList = const [_room]
            ..messageList = [
              ChatMessage(
                id: 'entry',
                sender: 'Sender',
                senderId: '@sender:test',
                body: '**short**',
                formattedBody: '<strong>short</strong>',
                timestamp: DateTime(2026, 10, 30, 12, 25),
                pending: false,
                reply: reply
                    ? const ReplyPreview(
                        eventId: 'old',
                        sender: 'Other',
                        body: 'Quoted',
                      )
                    : null,
              ),
            ];
          await pumpMobile(tester, backend);
          await tester.tap(find.text('Preview chat'));
          await tester.pumpAndSettle();
          final avatar = tester.getRect(
            find.byKey(const ValueKey('mobile-message-avatar-entry')),
          );
          final sender = tester.getRect(find.text('Sender'));
          final body = tester.getRect(
            find.byKey(const ValueKey('mobile-message-body-entry')),
          );
          expect(avatar.center.dy, closeTo((sender.top + body.bottom) / 2, 1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final mobile in [false, true]) {
    testWidgets(
      'header avatar plays with one lower-right presence dot, mobile=$mobile',
      (tester) async {
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = const [_room];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(DeltiecordApp(backend: backend));
        }
        await tester.tap(find.text('Preview chat'));
        await tester.pumpAndSettle();
        final header = find.byKey(const ValueKey('conversation-header-avatar'));
        if (mobile) {
          expect(tester.widget<MobileRoomAvatar>(header).autoplay, true);
        } else {
          expect(
            tester
                .widget<ThemeAvatar>(
                  find.descendant(
                    of: header,
                    matching: find.byType(ThemeAvatar),
                  ),
                )
                .autoplay,
            true,
          );
        }
        final dot = find.descendant(
          of: header,
          matching: find.byKey(
            ValueKey(
              mobile ? 'avatar-presence-online' : 'presence-room-online',
            ),
          ),
        );
        expect(dot, findsOneWidget);
        final a = tester.getRect(header), d = tester.getRect(dot);
        expect(d.center.dx, greaterThan(a.center.dx));
        expect(d.center.dy, greaterThan(a.center.dy));
        expect(
          find.byKey(const ValueKey('header-presence-online')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'embedded call fits its tiles and exposes every primary control, mobile=$mobile',
      (tester) async {
        final backend = _CallBackend()
          ..currentActiveVoiceId = 'room'
          ..currentVoiceStatus = VoiceConnectionStatus.connected;
        final room = RoomSummary(
          id: 'room',
          name: 'Call',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
          voiceParticipants: [
            VoiceParticipantSummary(userId: backend.userId!, displayName: 'Me'),
            const VoiceParticipantSummary(
              userId: '@peer:test',
              displayName: 'Peer',
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
            ),
            home: Center(
              child: SizedBox(
                key: const Key('call-frame'),
                width: mobile ? 360 : 800,
                height: 280,
                child: MediaQuery(
                  data: const MediaQueryData(
                    viewPadding: EdgeInsets.only(bottom: 34),
                    padding: EdgeInsets.only(bottom: 34),
                  ),
                  child: mobile
                      ? MobileVoiceView(
                          backend: backend,
                          room: room,
                          compact: true,
                          onOpenNavigation: () {},
                          onOpenDetails: () {},
                        )
                      : VoiceRoomView(
                          backend: backend,
                          room: room,
                          compact: true,
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final tooltip in ['Mute', 'Deafen', 'Camera on', 'Disconnect']) {
          expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
        }
        final grid = find.byKey(const ValueKey('compact-voice-grid'));
        final state = tester.state<ScrollableState>(
          find.descendant(of: grid, matching: find.byType(Scrollable)),
        );
        expect(state.position.maxScrollExtent, closeTo(0, 1));
        final controls = find.byKey(const ValueKey('voice-call-controls'));
        expect(
          tester.getBottomLeft(find.byKey(const Key('call-frame'))).dy -
              tester.getBottomLeft(controls).dy,
          lessThanOrEqualTo(8),
        );
        await tester.tap(find.byTooltip('Mute'));
        await tester.pump();
        expect(backend.muted, true);
        await tester.tap(find.byTooltip('Deafen'));
        await tester.pump();
        expect(backend.deafened, true);
        await tester.tap(find.byTooltip('Camera on'));
        await tester.pump();
        expect(backend.cameraEnabled, true);
        await tester.tap(find.byTooltip('Disconnect'));
        expect(backend.left, true);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
