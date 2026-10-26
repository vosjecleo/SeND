import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:deltiecord/ui/advanced_chat_dialogs.dart';
import 'package:deltiecord/services/emoji_repository.dart';
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  bool added = false;
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/hK0P7wAAAABJRU5ErkJggg==',
  );
  @override
  Future<Uint8List> downloadAttachment(
    String id, {
    bool thumbnail = false,
  }) async => pixel;
  @override
  Future<String?> getAttachmentReference(String id) async =>
      'mxc://test/sticker';
  @override
  Future<void> setStickerPackGloballyEnabled(
    StickerPackSummary pack,
    bool enabled,
  ) async {
    added = enabled;
  }
}

void main() {
  for (final rich in [false, true]) {
    testWidgets(
      'stock emoji opens large preview and canonical alias, rich=$rich',
      (tester) async {
        await tester.runAsync(() => EmojiRepository.instance.load());
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: rich
                    ? const MatrixHtmlText(html: '😭', fallback: '😭')
                    : const MatrixPlainText(text: '😭'),
              ),
            ),
          ),
        );
        await tester.tapAt(
          tester.getTopLeft(find.byType(SelectableText)) + const Offset(16, 20),
        );
        await tester.runAsync(() async {
          await EmojiRepository.instance.load();
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(find.text('Stock emoji'), findsOneWidget);
        expect(find.text(':sob:'), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.text('😭'),
                ),
              )
              .style!
              .fontSize,
          112,
        );
      },
    );
  }
  testWidgets('sticker opens big first, with its pack and account action', (
    tester,
  ) async {
    final backend = _Backend()
      ..stickerPackList = [
        const StickerPackSummary(
          id: 'pack',
          name: 'Cats',
          sourceRoomId: '!space:test',
          stickers: [],
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStickerPackForMessage(
                context,
                backend,
                messageId: 'id',
                attachment: const ChatAttachment(
                  kind: AttachmentKind.image,
                  name: 'cat',
                  mimeType: 'image/png',
                  size: 100,
                  encrypted: false,
                  spoiler: false,
                  sticker: true,
                  stickerPackId: 'pack',
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expression-details')), findsOneWidget);
    expect(find.text('Cats'), findsOneWidget);
    expect(find.text('Add to my account'), findsOneWidget);
    await tester.tap(find.text('Add to my account'));
    await tester.pumpAndSettle();
    expect(backend.added, true);
    expect(find.text('In your account'), findsOneWidget);
  });
}
