import 'dart:convert';
import 'dart:typed_data';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/clipboard_image.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:deltiecord/services/gif_service.dart';
import 'package:deltiecord/ui/composer_emoji_span.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'widget_test.dart' show FakeBackend;

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'stickers align with message text (${mobile ? 'mobile' : 'desktop'})',
      (tester) async {
        tester.view.physicalSize = Size(mobile ? 430 : 1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const room = RoomSummary(
          id: '!stickers:example.org',
          name: 'Stickers test',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        );
        final backend = _ImageBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = [room]
          ..currentRoom = room
          ..messageList = [
            ChatMessage(
              id: 'sticker',
              sender: 'Alice',
              body: '',
              timestamp: DateTime(2026, 9, 22),
              pending: false,
              attachment: const ChatAttachment(
                kind: AttachmentKind.image,
                name: 'cat',
                mimeType: 'image/png',
                size: 70,
                encrypted: false,
                spoiler: false,
                sticker: true,
                width: 1,
                height: 1,
              ),
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
        if (mobile &&
            find
                .byKey(const ValueKey('mobile-message-content-sticker'))
                .evaluate()
                .isEmpty) {
          await tester.tap(find.text('Stickers test').first);
          await tester.pumpAndSettle();
        }
        final content = find.byKey(
          ValueKey('${mobile ? 'mobile-' : ''}message-content-sticker'),
        );
        final frame = find.byKey(
          ValueKey(
            mobile ? 'mobile-image-frame-sticker' : 'sticker-frame-sticker',
          ),
        );
        expect(tester.getTopLeft(frame).dx, tester.getTopLeft(content).dx);
        expect(tester.getSize(frame).width, lessThanOrEqualTo(128));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('clipboard prefers original animated formats over flattened PNG', () {
    expect(clipboardImageFormats.first, Formats.gif);
    expect(
      clipboardImageFormats.indexOf(Formats.webp),
      lessThan(clipboardImageFormats.indexOf(Formats.png)),
    );
  });

  test('GIPHY selects animated previews and upgrades saved still previews', () {
    final result = GifSearchResult.fromApi({
      'title': 'Test',
      'images': {
        'fixed_width_still': {
          'url': 'https://media.giphy.com/media/test/200w_s.gif',
        },
        'fixed_width': {'url': 'https://media.giphy.com/media/test/200w.gif'},
        'downsized_medium': {
          'url': 'https://media.giphy.com/media/test/giphy.gif',
        },
      },
    })!;
    expect(result.previewUrl.path, endsWith('/200w.gif'));
    expect(result.shareUrl.path, endsWith('/giphy.gif'));
    final saved = GifSearchResult.fromJson({
      ...result.toJson(),
      'preview_url': 'https://media.giphy.com/media/test/200w_s.gif',
    })!;
    expect(saved.animatedPreviewUrl, saved.shareUrl);
  });

  test(
    'selected emoji spans preserve document offsets and literal aliases',
    () {
      final backend = FakeBackend();
      final emoji = CustomEmojiReference(
        id: Uri.parse('mxc://example.org/cat'),
        name: 'cat',
      );
      final text = '${emoji.fallback} ${emoji.fallback}';
      final span =
          composerEmojiSpan(
                backend: backend,
                text: text,
                link: customEmojiEditorLink(emoji),
              )
              as TextSpan;
      expect(span.toPlainText().length, text.length);
      expect(
        span.children!
            .whereType<WidgetSpan>()
            .where((s) => s.child is CustomEmojiImage)
            .length,
        2,
      );
      final literal = composerEmojiSpan(
        backend: backend,
        text: text,
        link: null,
      );
      expect(literal.toPlainText(), text);
    },
  );

  testWidgets('desktop Quill composer displays selected custom emoji', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const room = RoomSummary(
      id: '!test:example.org',
      name: 'Test room',
      lastMessage: '',
      unreadCount: 0,
      usesChannelIcon: false,
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = [room]
      ..currentRoom = room;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.pumpAndSettle();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    final emoji = CustomEmojiReference(
      id: Uri.parse('mxc://example.org/cat'),
      name: 'cat',
    );
    editor.controller.replaceText(
      0,
      0,
      emoji.fallback,
      const TextSelection.collapsed(offset: 5),
    );
    editor.controller.formatText(
      0,
      5,
      LinkAttribute(customEmojiEditorLink(emoji)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(QuillEditor),
        matching: find.byType(CustomEmojiImage),
      ),
      findsOneWidget,
    );
    expect(editor.controller.document.toPlainText(), ':cat:\n');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _ImageBackend extends FakeBackend {
  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/hK0P7wAAAABJRU5ErkJggg==',
  );
}
