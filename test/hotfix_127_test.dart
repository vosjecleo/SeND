import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/room_read_marker.dart';
import 'package:deltiecord/ui/inline_composer_preview.dart';
import 'package:deltiecord/ui/mobile/mobile_widgets.dart';
import 'support/fake_backend.dart';

class _Client extends Fake implements Client {
  final markers = <Map<String, String?>>[];
  final receipts = <(ReceiptType, String?)>[];
  @override
  bool get receiptsPublicByDefault => true;
  @override
  Future<void> setReadMarker(
    String roomId, {
    String? mFullyRead,
    String? mRead,
    String? mReadPrivate,
  }) async {
    markers.add({
      'fullyRead': mFullyRead,
      'public': mRead,
      'private': mReadPrivate,
    });
  }

  @override
  Future<void> postReceipt(
    String roomId,
    ReceiptType type,
    String eventId, {
    String? threadId,
  }) async {
    receipts.add((type, threadId));
  }
}

void main() {
  for (final threaded in [false, true]) {
    for (final public in [false, true]) {
      test(
        'unread acknowledgement persists with public=$public, threads=$threaded',
        () async {
          final client = _Client();
          final room = Room(id: '!room:test', client: client);
          await acknowledgeRoom(
            room,
            r'$newest',
            sendPublicReceipts: public,
            mainThreadOnly: threaded,
          );
          expect(client.markers.single['fullyRead'], r'$newest');
          if (threaded) {
            expect(
              client.receipts,
              contains((ReceiptType.mReadPrivate, 'main')),
            );
            expect(
              client.receipts.contains((ReceiptType.mRead, 'main')),
              public,
            );
            expect(client.markers.single['public'], isNull);
          } else {
            expect(client.markers.single['private'], r'$newest');
            expect(client.markers.single['public'], public ? r'$newest' : null);
          }
        },
      );
    }
  }
  test('double underscore preview is underline, not bold', () {
    final span = inlineComposerPreview('__hi__', const TextStyle());
    final content = span.children!.whereType<TextSpan>().singleWhere(
      (s) => s.text == 'hi',
    );
    expect(content.style!.decoration, TextDecoration.underline);
    expect(content.style!.fontWeight, isNot(FontWeight.bold));
    expect(span.toPlainText(), '__hi__');
  });
  testWidgets('server room identity uses its type icon, not an avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MobileRoomAvatar(
          room: RoomSummary(
            id: '!server-room:test',
            name: 'General',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: true,
          ),
        ),
      ),
    );
    expect(find.byType(MobileAvatar), findsNothing);
    expect(find.byIcon(Icons.tag), findsOneWidget);
  });
  testWidgets('mobile logout stays above the system navigation buttons', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final logout = find.widgetWithText(ListTile, 'Log out');
    expect(tester.getBottomRight(logout).dy, lessThanOrEqualTo(900 - 48));
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
