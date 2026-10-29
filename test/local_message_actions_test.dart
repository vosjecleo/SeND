import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/message_action_menu.dart';
import 'package:deltiecord/ui/archive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

ChatMessage message({bool own = true, bool pending = false}) => ChatMessage(
  id: 'event',
  sender: 'Someone',
  body: 'Hello',
  timestamp: DateTime(2026),
  pending: pending,
  own: own,
  canRedact: true,
);
void main() {
  test('regular message actions follow the requested order', () {
    expect(messageActionOrder(message(), canEdit: true, canPin: true), [
      MessageAction.reply,
      MessageAction.react,
      null,
      MessageAction.copy,
      MessageAction.unread,
      MessageAction.pin,
      MessageAction.bookmark,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.link,
    ]);
    final other = messageActionOrder(
      message(own: false),
      canEdit: true,
      canPin: true,
    );
    expect(other, isNot(contains(MessageAction.delete)));
    expect(other, isNot(contains(MessageAction.edit)));
  });
  test('pending sends cannot be edited, reacted to or marked delivered', () {
    expect(
      messageActionOrder(message(pending: true), canEdit: true, canPin: true),
      [MessageAction.copy, MessageAction.discard],
    );
  });
  testWidgets('three taps edit, a drag does not', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripleTapEdit(
            onEdit: () => edits++,
            child: const SizedBox(
              width: 200,
              height: 100,
              child: Text('Message'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Message'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(edits, 1);
    await tester.drag(find.text('Message'), const Offset(100, 0));
    await tester.tap(find.text('Message'));
    await tester.pump();
    expect(edits, 1);
  });
  testWidgets('archive header needs a pull and hides once scrolled away', (
    tester,
  ) async {
    final backend = FakeBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchivePullList(
            backend: backend,
            itemCount: 40,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('Room $i')),
          ),
        ),
      ),
    );
    expect(find.text('Archive'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsNothing);
  });
}
