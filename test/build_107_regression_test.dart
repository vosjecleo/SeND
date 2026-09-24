import 'dart:convert';
import 'dart:typed_data';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/receipt_positions.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/mobile/mobile_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show FakeBackend;

ChatMessage media(String id, int minute, {bool spoiler = false}) => ChatMessage(
  id: id,
  sender: 'Album author',
  senderId: '@album:test',
  body: '',
  timestamp: DateTime(2026, 9, 25, 12, minute),
  pending: false,
  attachment: ChatAttachment(
    kind: AttachmentKind.image,
    name: '$id.png',
    mimeType: 'image/png',
    size: 68,
    encrypted: false,
    width: 100,
    height: 100,
    spoiler: spoiler,
  ),
);

class GalleryBackend extends FakeBackend {
  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY1kAAAAASUVORK5CYII=',
  );
}

void main() {
  test('an old main-thread receipt cannot erase a newer global receipt', () {
    expect(
      readersAtOrBeyond(
        eventIndex: 1,
        eventPositions: {'new': 0, 'message': 1, 'old': 2},
        streams: [
          {'alice': 'new'},
          {'alice': 'old'},
        ],
      ),
      {'alice'},
    );
    expect(
      readersAtOrBeyond(
        eventIndex: 1,
        eventPositions: {'new': 0, 'message': 1, 'old': 2},
        streams: [
          {'alice': 'old'},
          {'alice': 'new'},
        ],
      ),
      {'alice'},
    );
  });
  test('unknown, older and own receipts do not claim a message was read', () {
    expect(
      readersAtOrBeyond(
        eventIndex: 1,
        ownUserId: 'me',
        eventPositions: {'new': 0, 'message': 1, 'old': 2},
        streams: [
          {'alice': 'missing', 'bob': 'old', 'me': 'new', 'carol': 'message'},
        ],
      ),
      {'carol'},
    );
  });
  for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
    testWidgets('album retains author header on $platform', (tester) async {
      tester.view.physicalSize = platform == TargetPlatform.android
          ? const Size(430, 900)
          : const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..currentRoom = const RoomSummary(
          id: '!room:test',
          name: 'Test room',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        )
        ..messageList = [
          media('new', 2, spoiler: true),
          media('old', 1, spoiler: true),
        ];
      await tester.pumpWidget(
        DeltiecordApp(backend: backend, platformOverride: platform),
      );
      await tester.pumpAndSettle();
      expect(find.text('Album author'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'mobile gallery swipes and offers accessible previous/next controls',
    (tester) async {
      final backend = GalleryBackend()
        ..messageList = [media('new', 2), media('old', 1)];
      await tester.pumpWidget(
        MaterialApp(
          home: MobileMediaGallery(
            backend: backend,
            initialMessage: backend.messages.last,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous media'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Windows accent is exact and high-contrast hover remains neutral',
    (tester) async {
      final backend = FakeBackend()
        ..currentPreferences = const AppPreferences().copyWith(
          accentColor: 0xff127e44,
          highContrast: true,
        );
      await tester.pumpWidget(
        DeltiecordApp(
          backend: backend,
          platformOverride: TargetPlatform.windows,
        ),
      );
      await tester.pump();
      final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
      expect(theme.colorScheme.primary, const Color(0xff127e44));
      expect(theme.iconTheme.color, const Color(0xff127e44));
      expect(
        theme.iconButtonTheme.style!.foregroundColor!.resolve({}),
        const Color(0xff127e44),
      );
      expect(
        theme.extension<DeltiecordPalette>()!.hover,
        DeltiecordPalette.forMode(backend.preferences.themeMode).hover,
      );
    },
  );
}
