import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/android_push_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

class LiveBackend extends FakeBackend {
  List<InboxItemSummary> invitations = [];
  int joins = 0;
  String? inviteAction;
  @override
  List<InboxItemSummary> get unifiedInbox => invitations;
  void publish() => notifyListeners();
  @override
  Future<void> joinVoiceRoom(String roomId) async {
    joins++;
  }

  @override
  Future<void> acceptRoomInvite(String roomId) async {
    inviteAction = 'accept';
    invitations = [];
    publish();
  }

  @override
  Future<void> rejectRoomInvite(String roomId) async {
    inviteAction = 'ignore';
    invitations = [];
    publish();
  }

  @override
  Future<void> setChannelCategoryCollapsed(String id, bool collapsed) async {
    categoryList = [
      for (final category in categoryList)
        ChannelCategorySummary(
          id: category.id,
          name: category.name,
          roomIds: category.roomIds,
          collapsed: category.id == id ? collapsed : category.collapsed,
        ),
    ];
    publish();
  }
}

Future<void> mount(
  WidgetTester tester,
  LiveBackend backend,
  bool mobile,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = mobile
      ? const Size(430, 900)
      : const Size(1280, 900);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    DeltiecordApp(
      backend: backend,
      platformOverride: mobile ? TargetPlatform.android : TargetPlatform.linux,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final mobile in [false, true]) {
    testWidgets('voice counts change without navigation, mobile=$mobile', (
      tester,
    ) async {
      RoomSummary voice(int count) => RoomSummary(
        id: '!voice:test',
        name: 'Live voice',
        lastMessage: '',
        unreadCount: 0,
        usesChannelIcon: true,
        presentation: RoomPresentation.voice,
        voiceParticipants: [
          for (var i = 0; i < count; i++)
            VoiceParticipantSummary(
              userId: '@u$i:test',
              displayName: 'User $i',
            ),
        ],
      );
      final backend = LiveBackend()
        ..currentStatus = SessionStatus.signedIn
        ..currentSpaceId = '!space:test'
        ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Space')]
        ..roomList = [voice(1)];
      await mount(tester, backend, mobile);
      expect(find.text('1 connected'), findsOneWidget);
      backend.roomList = [voice(2)];
      backend.publish();
      await tester.pumpAndSettle();
      expect(find.text('2 connected'), findsOneWidget);
      expect(find.text('1 connected'), findsNothing);
      backend.roomList = [voice(0)];
      backend.publish();
      await tester.pumpAndSettle();
      expect(find.text('2 connected'), findsNothing);
    });
    testWidgets('category updates without navigation, mobile=$mobile', (
      tester,
    ) async {
      final backend = LiveBackend()
        ..currentStatus = SessionStatus.signedIn
        ..currentSpaceId = '!space:test'
        ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Space')]
        ..roomList = const [
          RoomSummary(
            id: '!room:test',
            name: 'general',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: true,
          ),
        ]
        ..categoryList = const [
          ChannelCategorySummary(
            id: 'category',
            name: 'Topics',
            roomIds: ['!room:test'],
          ),
        ];
      await mount(tester, backend, mobile);
      expect(find.text('general'), findsOneWidget);
      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      expect(find.text('general'), findsNothing);
      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      expect(find.text('general'), findsOneWidget);
    });
    testWidgets('live inbox badge and ignore action, mobile=$mobile', (
      tester,
    ) async {
      final backend = LiveBackend()..currentStatus = SessionStatus.signedIn;
      await mount(tester, backend, mobile);
      expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('inbox-invite-badge')))
            .isLabelVisible,
        false,
      );
      backend.invitations = [
        InboxItemSummary(
          id: 'invite',
          roomId: '!invite:test',
          roomName: 'Invitation room',
          kind: InboxItemKind.invite,
          timestamp: DateTime(2026),
          preview: 'Invited',
        ),
      ];
      backend.publish();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('inbox-invite-badge')))
            .isLabelVisible,
        true,
      );
      await tester.tap(find.byTooltip('Inbox').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Accept invitation'), findsOneWidget);
      await tester.tap(find.byTooltip('Ignore invitation'));
      await tester.pumpAndSettle();
      expect(backend.inviteAction, 'ignore');
      expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('inbox-invite-badge')))
            .isLabelVisible,
        false,
      );
    });
    testWidgets(
      'voice channel opens overview without joining, mobile=$mobile',
      (tester) async {
        final backend = LiveBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = const [
            RoomSummary(
              id: '!voice:test',
              name: 'Lounge',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: true,
              presentation: RoomPresentation.voice,
            ),
          ];
        await mount(tester, backend, mobile);
        await tester.tap(find.text('Lounge').first);
        await tester.pumpAndSettle();
        expect(backend.selectedRoom?.id, '!voice:test');
        expect(backend.joins, 0);
      },
    );
  }
  test(
    'invitation push has unread target and respects sound/vibration choices',
    () {
      final result = invitationNotification(
        roomId: '!room:test',
        eventId: r'$invite',
        roomName: 'A room',
        settings: {
          'notification_sound': false,
          'notification_vibration': false,
        },
      );
      expect(result['roomId'], '!room:test');
      expect(result['eventId'], r'$invite');
      expect(result['unreadCount'], 1);
      expect(result['sound'], false);
      expect(result['vibrate'], false);
    },
  );
}
