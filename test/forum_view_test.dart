import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/forum_post.dart';
import 'package:deltiecord/ui/chat_shell.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show FakeBackend;

class _ForumBackend extends FakeBackend {
  bool fail = true;
  ForumPost? created;
  @override
  Future<void> createForumPost(
    String roomId,
    ForumPost post,
    String body, {
    AttachmentDraft? cover,
  }) async {
    if (fail) throw StateError('Offline');
    created = post;
  }
}

void main() {
  testWidgets('failed forum send preserves editable draft for retry', (
    tester,
  ) async {
    final backend = _ForumBackend();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: ForumView(
            backend: backend,
            room: const RoomSummary(
              id: '!forum',
              name: 'Forum',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: true,
              presentation: RoomPresentation.forum,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('New post'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'A question',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Post'),
      'Details of the question',
    );
    await tester.tap(find.text('Create post'));
    await tester.pumpAndSettle();
    expect(find.text('New forum post'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Title'))
          .controller!
          .text,
      'A question',
    );
    backend.fail = false;
    await tester.tap(find.text('Create post'));
    await tester.pumpAndSettle();
    expect(backend.created!.title, 'A question');
    expect(find.text('New forum post'), findsNothing);
  });
}
