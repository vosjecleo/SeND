import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/forum_post.dart';
import 'package:deltiecord/ui/chat_shell.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'widget_test.dart' show FakeBackend;

class _ForumBackend extends FakeBackend {
  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/\nhK0P7wAAAABJRU5ErkJggg=='
        .replaceAll('\n', ''),
  );
  bool fail = true;
  ForumPost? created;
  String? editedId;
  String? editedBody;
  bool removedCover = false;
  @override
  Future<void> editForumPost(
    String roomId,
    String messageId,
    ForumPost post,
    String body, {
    AttachmentDraft? cover,
    bool removeCover = false,
  }) async {
    if (fail) throw StateError('Offline');
    editedId = messageId;
    editedBody = body;
    created = post;
    removedCover = removeCover;
  }

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
  testWidgets(
    'opening forums acknowledges posts and permission-gates deletion',
    (tester) async {
      final backend = _ForumBackend()
        ..messageList = [
          ChatMessage(
            id: 'owned',
            sender: 'Me',
            body: 'My post',
            timestamp: DateTime(2026, 10, 6),
            pending: false,
            own: true,
            canRedact: true,
          ),
          ChatMessage(
            id: 'other',
            sender: 'Other',
            body: 'Their post',
            timestamp: DateTime(2026, 10, 5),
            pending: false,
            canRedact: false,
          ),
        ];
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
                unreadCount: 1,
                usesChannelIcon: true,
                presentation: RoomPresentation.forum,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(backend.conversationAtPresentStates.last, isTrue);
      expect(find.byTooltip('Delete forum post'), findsNothing);
      expect(find.byTooltip('Post actions'), findsOneWidget);
      await tester.longPress(find.text('My post').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit post'), findsOneWidget);
      await tester.tap(find.text('Delete post'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.redactedMessageIds, isEmpty);
      await tester.tap(find.byTooltip('Post actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete post'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(backend.redactedMessageIds, ['owned']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(backend.conversationAtPresentStates.last, isFalse);
    },
  );

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
    await tester.enterText(find.widgetWithText(TextField, 'Add a tag'), 'help');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'help'), findsOneWidget);
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
    expect(backend.created!.tags, ['help']);
    expect(find.text('New forum post'), findsNothing);
  });

  testWidgets(
    'authors edit title body tags and remove cover; moderators only delete',
    (tester) async {
      final backend = _ForumBackend()
        ..fail = false
        ..messageList = [
          ChatMessage(
            id: 'owned',
            sender: 'Me',
            body: 'Title\n\nBody',
            timestamp: DateTime(2026),
            pending: false,
            own: true,
            canRedact: true,
            forumPost: const ForumPost(title: 'Title', tags: ['old']),
            attachment: const ChatAttachment(
              name: 'cover.png',
              mimeType: 'image/png',
              kind: AttachmentKind.image,
              size: 20,
              encrypted: false,
              spoiler: false,
            ),
          ),
          ChatMessage(
            id: 'other',
            sender: 'Other',
            body: 'Other post',
            timestamp: DateTime(2025),
            pending: false,
            canRedact: true,
          ),
        ];
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
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Other post').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit post'), findsNothing);
      expect(find.text('Delete post'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Post actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit post'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Post'))
            .controller!
            .text,
        'Body',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Updated',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Post'),
        'New body',
      );
      await tester.tap(find.byType(InputChip).first);
      final chip = tester.widget<InputChip>(find.byType(InputChip).first);
      chip.onDeleted!();
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Add a tag'),
        'new',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.ensureVisible(find.text('Remove cover'));
      await tester.tap(find.text('Remove cover'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(backend.editedId, 'owned');
      expect(backend.editedBody, 'New body');
      expect(backend.created!.title, 'Updated');
      expect(backend.created!.tags, ['new']);
      expect(backend.removedCover, isTrue);
    },
  );
}
