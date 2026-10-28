import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/room_mentions.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';

void main() {
  test(
    'reply fallback links and recipient metadata do not create authored mentions',
    () {
      expect(
        messageHasVisualMention(
          body: 'hello',
          isReply: true,
          mentions: {
            'user_ids': ['@friend:test'],
          },
          formattedBody:
              '<mx-reply><blockquote><a href="https://matrix.to/#/@friend:test">Friend</a></blockquote></mx-reply>hello',
        ),
        false,
      );
      expect(
        messageHasVisualMention(body: 'hello @friend:test', isReply: true),
        true,
      );
      expect(
        messageHasVisualMention(
          body: 'hello Friend',
          isReply: true,
          formattedBody:
              '<a href="https://matrix.to/#/@friend:test">Friend</a>',
        ),
        true,
      );
    },
  );
  test('malformed mention recipients are ignored, not cast into a crash', () {
    for (final value in ['bad', 7, <String, Object?>{}, null]) {
      expect(
        messageMentionsUser(
          body: 'hi',
          userId: '@me:test',
          senderId: '@other:test',
          mentions: {'user_ids': value},
        ),
        false,
      );
    }
  });
  test(
    'own self-chat mentions get visual treatment without self notifications',
    () {
      expect(messageHasVisualMention(body: '@everyone'), true);
      expect(messageHasVisualMention(body: 'Hi @me:test'), true);
      expect(
        messageHasVisualMention(
          body: '@cleo',
          formattedBody:
              '<a href="https://matrix.to/#/@cleo:deltie.net">@cleo</a>',
        ),
        true,
      );
      expect(
        messageMentionsUser(
          body: '@everyone',
          userId: '@me:test',
          senderId: '@me:test',
        ),
        false,
      );
      expect(messageHasVisualMention(body: r'\@everyone'), false);
    },
  );
  test(
    'room-wide aliases include punctuation but not escapes or longer names',
    () {
      for (final text in [
        '@everyone',
        'Hi @everyone!',
        '(@everyone)',
        '@room.',
      ]) {
        expect(containsRoomMention(text), true, reason: text);
      }
      for (final text in [
        r'\@everyone',
        '@everyone_else',
        '@everyone:test',
        'https://example.org/@everyone',
        'mail@everyone.org',
      ]) {
        expect(containsRoomMention(text), false, reason: text);
      }
    },
  );
  test(
    'recipient metadata controls row highlighting and legacy room pings respect permission',
    () {
      bool ping({
        String body = 'hi',
        Map<String, Object?>? mentions,
        bool permission = true,
        String sender = '@other:test',
      }) => messageMentionsUser(
        body: body,
        userId: '@me:test',
        senderId: sender,
        mentions: mentions,
        canNotifyRoom: permission,
      );
      expect(ping(mentions: {'room': true}), true);
      expect(
        ping(
          mentions: {
            'user_ids': ['@me:test'],
          },
        ),
        true,
      );
      expect(
        ping(
          mentions: {
            'user_ids': ['@else:test'],
          },
        ),
        false,
      );
      expect(ping(body: '@everyone!', mentions: {}), false);
      expect(ping(body: '@everyone!'), true);
      expect(ping(body: '@everyone!', permission: false), false);
      expect(ping(body: '@everyone!', sender: '@me:test'), false);
      expect(ping(body: 'Hi @me:test.'), true);
    },
  );
  for (final rich in [false, true]) {
    testWidgets(
      'everyone token gets the same highlight as Matrix mentions, rich=$rich',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: rich
                  ? const MatrixHtmlText(
                      html: '<strong>Hi @everyone!</strong>',
                      fallback: 'Hi @everyone!',
                    )
                  : const MatrixPlainText(text: 'Hi @everyone!'),
            ),
          ),
        );
        final text = tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!;
        TextSpan? token;
        void walk(InlineSpan span) {
          if (span is TextSpan) {
            if (span.text == '@everyone') token = span;
            for (final child in span.children ?? <InlineSpan>[]) {
              walk(child);
            }
          }
        }

        walk(text);
        expect(token, isNotNull);
        expect(token!.style!.backgroundColor, const Color(0x403fa9f5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
