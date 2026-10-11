import 'package:deltiecord/ui/plain_message_editor.dart';
import 'dart:convert';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:deltiecord/services/emoji_repository.dart';
import 'package:deltiecord/services/favourite_reactions_store.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/advanced_chat_dialogs.dart';
import 'package:deltiecord/ui/emoji_picker_dialog.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('custom emoji picker groups entries by pack', (tester) async {
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/'
      'hK0P7wAAAABJRU5ErkJggg==',
    );
    StickerPackSummary pack(String id, String name, String emojiName) =>
        StickerPackSummary(
          id: id,
          name: name,
          stickers: [
            StickerSummary(
              id: emojiName,
              name: emojiName,
              mxcUri: Uri.parse('mxc://example.org/$id'),
              previewBytes: imageBytes,
              assetType: StickerAssetType.emoji,
              packId: id,
            ),
          ],
        );
    final backend = FakeBackend()
      ..stickerPackList = [
        pack('cats', 'Cat pack', 'party_cat'),
        pack('birds', 'Bird pack', 'party_bird'),
      ];
    expect(customEmojiEntries(backend.stickerPacks), hasLength(2));
    const palette = DeltiecordPalette(
      background: Color(0xff26272c),
      rail: Color(0xff1e1f22),
      panel: Color(0xff202125),
      surface: Color(0xff26272c),
      elevated: Color(0xff303137),
      input: Color(0xff303137),
      island: Color(0xff303137),
      hover: Color(0xff34353b),
      divider: Color(0xff36373d),
      text: Color(0xfff2f3f5),
      muted: Color(0xffb5bac1),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [palette]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<EmojiEntry>(
                context: context,
                builder: (context) => EmojiPickerDialog(backend: backend),
              ),
              child: const Text('Open emoji'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open emoji'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Custom'));
    await tester.pumpAndSettle();

    expect(find.text('Cat pack'), findsOneWidget);
    expect(find.text('Bird pack'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emoji-picker-result-mxc://example.org/cats')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('emoji-picker-result-mxc://example.org/birds')),
      findsOneWidget,
    );
  });

  testWidgets('inline custom emoji opens its accessible source pack', (
    tester,
  ) async {
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/'
      'hK0P7wAAAABJRU5ErkJggg==',
    );
    final emoji = CustomEmojiReference(
      id: Uri.parse('mxc://example.org/party-cat'),
      name: 'party_cat',
      packId: 'room:!cats:example.org:pack',
    );
    final backend = FakeBackend()
      ..stickerPackList = [
        StickerPackSummary(
          id: emoji.packId!,
          name: 'Cat reactions',
          sourceRoomId: '!cats:example.org',
          stateKey: 'pack',
          stickers: [
            StickerSummary(
              id: 'party_cat',
              name: 'party_cat',
              mxcUri: emoji.id,
              previewBytes: imageBytes,
              assetType: StickerAssetType.emoji,
              packId: emoji.packId,
            ),
          ],
        ),
      ];
    final palette = DeltiecordPalette.forMode(DeltiecordThemeMode.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [palette]),
        home: Scaffold(
          body: Builder(
            builder: (context) => MatrixHtmlText(
              html: 'hello ${customEmojiHtml(emoji)}',
              fallback: 'hello ${emoji.fallback}',
              selectable: false,
              backend: backend,
              onCustomEmojiTap: (selected) =>
                  showStickerPackForEmoji(context, backend, selected),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<CustomEmojiImage>(find.byType(CustomEmojiImage)).size,
      20,
    );
    await tester.tap(
      find.ancestor(
        of: find.byType(CustomEmojiImage),
        matching: find.byType(GestureDetector),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cat reactions'), findsOneWidget);
    expect(find.text('Add to my account'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [palette]),
        home: Scaffold(
          body: MatrixHtmlText(
            html: customEmojiHtml(emoji),
            fallback: emoji.fallback,
            selectable: false,
            backend: backend,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<CustomEmojiImage>(find.byType(CustomEmojiImage)).size,
      64,
    );
  });

  testWidgets('emoji completion overlays without resizing the composer', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji-overlay:example.org',
          name: 'emoji overlay',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('emoji overlay'));
    await tester.pumpAndSettle();
    final composer = find.byKey(const Key('message-composer-panel'));
    final initialHeight = tester.getSize(composer).height;

    await enterComposer(tester, ':so');
    final editor = tester.widget<PlainMessageEditor>(
      find.byType(PlainMessageEditor),
    );
    editor.controller.replaceText(
      3,
      0,
      'b',
      const TextSelection.collapsed(offset: 4),
    );
    await tester.pumpAndSettle();

    expect(editor.controller.document.toPlainText(), ':sob\n');
    expect(
      find.byKey(const Key('emoji-completion-popup'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('😭', skipOffstage: false), findsOneWidget);
    final popup = find.byKey(
      const Key('emoji-completion-popup'),
      skipOffstage: false,
    );
    expect(tester.getSize(popup).width, 280);
    expect(tester.getSize(popup).height, lessThan(150));
    if (find
        .byKey(const Key('emoji-completion-result-1'))
        .evaluate()
        .isNotEmpty) {
      expect(
        tester
            .getTopLeft(find.byKey(const Key('emoji-completion-result-0')))
            .dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const Key('emoji-completion-result-1')))
              .dy,
        ),
      );
    }
    expect(tester.getSize(composer).height, initialHeight);
  });

  testWidgets('converts a closed local emoji alias in the composer', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji:example.org',
          name: 'emoji',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('emoji'));
    await tester.pump();
    await enterComposer(tester, ':sob:');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PlainMessageEditor>(find.byType(PlainMessageEditor))
          .controller
          .document
          .toPlainText(),
      '😭\n',
    );
  });

  testWidgets('Android custom emoji autocomplete sends a stable MXC ID', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji:example.org',
          name: 'emoji',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..stickerPackList = [
        StickerPackSummary(
          id: 'room:pack',
          name: 'Server emoji',
          stickers: [
            StickerSummary(
              id: 'party',
              name: 'party',
              mxcUri: Uri.parse('mxc://example.org/stable-party'),
              assetType: StickerAssetType.emoji,
              packId: 'room:pack',
            ),
          ],
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('emoji'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-composer-field')),
      ':par',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-emoji-completion-0')));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send; hold to send later'));
    await tester.pumpAndSettle();

    expect(backend.sentMessages, [':party:']);
    expect(backend.sentFormattedBodies.single, contains('data-mx-emoticon'));
    expect(
      backend.sentFormattedBodies.single,
      contains('mxc://example.org/stable-party'),
    );
  });

  testWidgets('desktop sticker picker uses a bounded dialog', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final backend = FakeBackend();
    await tester.runAsync(FavouriteReactionsStore.instance.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStickerPicker(context, backend),
              child: const Text('Open stickers'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open stickers'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sticker-picker-surface')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android sticker manager exposes its final import action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final backend = FakeBackend();
    await tester.runAsync(FavouriteReactionsStore.instance.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStickerPicker(context, backend),
              child: const Text('Open stickers'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open stickers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create or import a pack'));
    await tester.pumpAndSettle();

    final finalAction = find.text('Import Telegram pack as emoji');
    await tester.scrollUntilVisible(
      finalAction,
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('sticker-pack-manager-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(finalAction, findsOneWidget);
    expect(
      find.byKey(const ValueKey('sticker-pack-manager-surface')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android composer completes local colon emoji aliases', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji-mobile:test',
          name: 'Emoji mobile',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Emoji mobile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-composer-field')),
      ':sob:',
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile-composer-field')),
    );
    expect(field.controller!.text, '😭');
  });

  testWidgets('Android composer searches the complete local emoji catalogue', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji-search-mobile:test',
          name: 'Emoji search mobile',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Emoji search mobile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-composer-field')),
      'hello :cat',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-emoji-completion-popup')),
      findsOneWidget,
    );
    expect(find.textContaining(':cat'), findsWidgets);
  });
}
