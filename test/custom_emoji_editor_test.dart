import 'package:deltiecord/ui/plain_message_editor.dart';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:deltiecord/ui/composer_emoji_span.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

void main() {
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

  testWidgets('desktop plain composer displays selected custom emoji', (
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
    final editor = tester.widget<PlainMessageEditor>(
      find.byType(PlainMessageEditor),
    );
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
        of: find.byType(PlainMessageEditor),
        matching: find.byType(CustomEmojiImage),
      ),
      findsOneWidget,
    );
    expect(editor.controller.document.toPlainText(), ':cat:\n');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
