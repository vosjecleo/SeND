import 'dart:convert';
import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:deltiecord/ui/message_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  @override
  Future<Uint8List?> loadStickerPreview(
    StickerSummary sticker,
  ) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/hK0P7wAAAABJRU5ErkJggg==',
  );
}

void main() {
  for (final body in [
    'hi 🙂',
    'hi 👩‍👩‍👧‍👦',
    'hi 🇳🇱',
    'hi 👍🏽',
    '🙂',
    ':custom:',
    'hi :custom:',
  ]) {
    testWidgets(
      'receipt follows the complete final emoji without adding a row: $body',
      (tester) async {
        final custom = body.endsWith(':custom:');
        final message = ChatMessage(
          id: 'emoji',
          sender: 'Me',
          body: body,
          timestamp: DateTime(2026),
          pending: false,
          own: true,
        );
        late ReceiptPlacementScope scope;
        Future<void> show(bool receipt) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 300,
                    child: ReceiptPlacement(
                      messages: [message],
                      receiptIds: receipt ? {'emoji'} : {},
                      contentInset: 0,
                      child: Builder(
                        builder: (context) {
                          scope = ReceiptPlacementScope.of(context)!;
                          final metadata = receipt
                              ? messageMetadata(
                                  context,
                                  message,
                                  showReceipt: true,
                                )
                              : null;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (custom)
                                MatrixHtmlText(
                                  key: const ValueKey('body'),
                                  backend: _Backend(),
                                  html:
                                      '${body.startsWith('hi ') ? 'hi ' : ''}<img data-mx-emoticon src="mxc://test/custom" alt=":custom:">',
                                  fallback: body,
                                  trailing: metadata,
                                )
                              else
                                MatrixPlainText(
                                  key: const ValueKey('body'),
                                  text: body,
                                  trailing: metadata,
                                ),
                              const Text(
                                'Following message',
                                key: ValueKey('next'),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show(false);
        final before = tester.getTopLeft(find.byKey(const ValueKey('next'))).dy;
        await show(true);
        expect(scope.relocated, isEmpty);
        final text = tester.getRect(find.byType(SelectableText));
        final marker = tester.getRect(find.byIcon(Icons.check));
        expect(marker.bottom, lessThanOrEqualTo(text.bottom + .01));
        if (!custom) {
          final editable = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final boxes = editable.getBoxesForSelection(
            TextSelection(
              baseOffset: body.length - body.characters.last.length,
              extentOffset: body.length,
            ),
          );
          expect(boxes, isNotEmpty);
          final edge = editable
              .localToGlobal(Offset(boxes.last.right, boxes.last.bottom))
              .dx;
          expect(marker.left, greaterThanOrEqualTo(edge));
          expect(marker.left - edge, lessThan(12));
        }
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('next'))).dy,
          closeTo(before, .01),
        );
        if (custom) {
          final image = tester.getRect(find.byType(CustomEmojiImage));
          expect(marker.left, greaterThanOrEqualTo(image.right));
          expect(marker.left - image.right, lessThan(12));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
