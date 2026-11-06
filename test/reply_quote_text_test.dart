import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/reply_quote_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fontSize in [12.0, 14.0]) {
    testWidgets('reply avatar precedes the author and quote at $fontSize', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: ReplyQuoteText(
                  reply: const ReplyPreview(
                    eventId: 'target',
                    sender: 'Friend',
                    senderId: '@friend:test',
                    body: 'Quoted message',
                  ),
                  fontSize: fontSize,
                  muted: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byType(ReplyQuoteText),
              matching: find.byType(RichText),
            )
            .first,
      );
      final text = paragraph.text.toPlainText();
      expect(text, '\uFFFCFriend  Quoted message');
      final authorBox = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 1, extentOffset: 7),
          )
          .first;
      final authorLeft = paragraph
          .localToGlobal(Offset(authorBox.left, authorBox.top))
          .dx;
      final avatar = tester.getRect(
        find.byKey(const ValueKey('reply-mini-avatar')),
      );
      expect(avatar.right, lessThan(authorLeft));
      expect(avatar.size, const Size.square(14));
      expect(tester.takeException(), isNull);
    });
  }
}
