import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/receipt_frontiers.dart';
import 'package:deltiecord/services/favourite_reactions_store.dart';
import 'package:deltiecord/ui/accent_color_picker.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:deltiecord/ui/rich_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show FakeBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('receipt boundaries advance to latest sent and latest read', () {
    ChatMessage message(String id, {bool read = false, bool pending = false}) =>
        ChatMessage(
          id: id,
          sender: 'Me',
          body: 'hi',
          timestamp: DateTime(2026),
          own: true,
          pending: pending,
          readBy: read
              ? const [
                  ReceiptReaderSummary(
                    userId: '@friend:test',
                    displayName: 'Friend',
                  ),
                ]
              : const [],
        );
    expect(
      receiptFrontiers([
        message('pending', pending: true),
        message('new'),
        message('middle'),
        message('read', read: true),
        message('old', read: true),
      ]),
      {'new', 'read'},
    );
    expect(
      receiptFrontiers([
        message('read', read: true),
        message('old', read: true),
      ]),
      {'read'},
    );
  });

  test('editing preserves supported rich formatting and spoilers', () {
    final restored = richMessageDocument(
      'bold secret',
      '<p><strong>bold</strong> <span data-mx-spoiler>secret</span></p>',
    );
    final result = serializeRichMessage(restored);
    expect(result.plainText, 'bold secret');
    expect(result.html, contains('<strong>bold</strong>'));
    expect(result.html, contains('data-mx-spoiler'));
  });

  test(
    'sending counts complete Unicode emoji and custom IDs, not literal aliases',
    () async {
      final store = FavouriteReactionsStore.instance;
      final before = store.emojiUsage['😭'] ?? 0;
      await store.recordSentMessage(
        '😭 :not_sent: :wave:',
        '<img data-mx-emoticon src="mxc://test/wave" alt=":wave:">',
      );
      expect(store.emojiUsage['😭'], before + 1);
      expect(store.emojiUsage.containsKey(':not_sent:'), isFalse);
      expect(store.emojiUsage['mxc://test/wave'], greaterThan(0));
    },
  );

  testWidgets('formatted link reveals destination before launching', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MatrixHtmlText(
            html: '<a href="https://example.org/actual">Friendly label</a>',
            fallback: 'Friendly label',
            selectable: false,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Friendly label'));
    await tester.pumpAndSettle();
    expect(find.text('https://example.org/actual'), findsOneWidget);
    expect(find.text('Open link'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('colour picker has explicit Apply and closes without rollback', (
    tester,
  ) async {
    var color = 0xff123456;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccentColorPickerButton(
            color: color,
            onChanged: (value) => color = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('accent-hex-field')),
      '#ABCDEF',
    );
    expect(color, 0xffabcdef);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'logout requires confirmation and cancellation preserves settings',
    (tester) async {
      final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
      await tester.pumpWidget(DeltiecordApp(backend: backend));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.status, SessionStatus.signedIn);
      expect(find.text('Settings'), findsWidgets);
    },
  );

  testWidgets('successful logout dismisses settings and returns to login', (
    tester,
  ) async {
    final backend = _LogoutBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(backend.status, SessionStatus.signedOut);
    expect(find.text('Settings'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop composer grows on soft wrap without stretching user island',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const room = RoomSummary(
        id: '!test:example.org',
        name: 'Test',
        lastMessage: '',
        unreadCount: 0,
        usesChannelIcon: false,
      );
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = [room]
        ..currentRoom = room;
      await tester.pumpWidget(
        DeltiecordApp(backend: backend, platformOverride: TargetPlatform.linux),
      );
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('message-composer-island'));
      final user = find.byKey(const Key('current-user-island'));
      final initialHeight = tester.getSize(composer).height;
      final userHeight = tester.getSize(user).height;
      tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller
          .replaceText(0, 0, 'a long wrapping message ' * 30, null);
      await tester.pumpAndSettle();
      expect(tester.getSize(composer).height, greaterThan(initialHeight));
      expect(tester.getSize(user).height, userHeight);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('theme and sizing continue to update after repeated resume', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
    );
    for (var i = 0; i < 4; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await backend.updatePreferences(
        backend.preferences.copyWith(
          themeMode: i.isEven
              ? DeltiecordThemeMode.light
              : DeltiecordThemeMode.dark,
          fontScale: i.isEven ? 1.2 : 1,
        ),
      );
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.theme!.brightness,
        i.isEven ? Brightness.light : Brightness.dark,
      );
    }
    expect(tester.takeException(), isNull);
  });
}

class _LogoutBackend extends FakeBackend {
  @override
  Future<void> logout() async {
    currentStatus = SessionStatus.signedOut;
    notifyListeners();
  }
}
