import 'dart:async';
import 'package:deltiecord/backend/thread_session.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/chat_shell.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show FakeBackend;

class _Session extends ThreadSession {
  bool closed = false;
  bool fail = false;
  Completer<void>? sendGate;
  final read = <String>[];
  final sent = <String>[];
  final items = <ChatMessage>[];
  @override
  String get roomId => '!room';
  @override
  String get rootId => r'$root';
  @override
  List<ChatMessage> get messages => items;
  @override
  bool get loading => false;
  @override
  bool get canLoadMore => false;
  @override
  String? get error => null;
  @override
  Future<void> loadMore() async {}
  @override
  Future<void> attach(AttachmentDraft attachment) async {}
  @override
  Future<void> markRead(String eventId) async => read.add(eventId);
  @override
  Future<void> send(
    String text, {
    String? formattedBody,
    String? editMessageId,
  }) async {
    if (fail) throw StateError('Offline');
    await sendGate?.future;
    sent.add(text);
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

class _Backend extends FakeBackend {
  final session = _Session();
  @override
  Future<ThreadSession> openThread(String roomId, String rootId) async =>
      session;
}

void main() {
  testWidgets(
    'new replies stay below old replies and sending keeps the keyboard',
    (tester) async {
      final backend = _Backend();
      backend.session.items.addAll([
        ChatMessage(
          id: 'new',
          sender: 'Alice',
          body: 'Newest reply',
          timestamp: DateTime(2026, 10, 6, 12),
          pending: false,
        ),
        ChatMessage(
          id: 'old',
          sender: 'Alice',
          body: 'Older reply',
          timestamp: DateTime(2026, 10, 6, 11),
          pending: false,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: Scaffold(
            body: ThreadView(
              backend: backend,
              roomId: '!room',
              rootId: r'$root',
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Newest reply')).dy,
        greaterThan(tester.getTopLeft(find.text('Older reply')).dy),
      );
      expect(backend.session.read.last, 'new');
      await tester.enterText(find.byType(TextField), 'First draft');
      backend.session.sendGate = Completer<void>();
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(find.byType(TextField), 'Next draft');
      backend.session.sendGate!.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Next draft',
      );
      expect(tester.testTextInput.isVisible, isTrue);
    },
  );

  testWidgets('touch actions can edit and cancel without leaving edited text', (
    tester,
  ) async {
    final backend = _Backend();
    backend.session.items.add(
      ChatMessage(
        id: r'$reply',
        sender: 'Me',
        body: 'Original text',
        timestamp: DateTime(2026, 9, 24),
        pending: false,
        own: true,
        threadRootId: r'$root',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: ThreadView(
            backend: backend,
            roomId: '!room',
            rootId: r'$root',
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Original text',
    );
    await tester.tap(find.byTooltip('Cancel edit'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('View discussion'), findsNothing);
  });
  testWidgets(
    'thread send clears only successful drafts and releases session',
    (tester) async {
      final backend = _Backend();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: Scaffold(
            body: ThreadView(
              backend: backend,
              roomId: '!room',
              rootId: r'$root',
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Hello discussion');
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pumpAndSettle();
      expect(backend.session.sent, ['Hello discussion']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      backend.session.fail = true;
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep this draft',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(backend.session.closed, isTrue);
    },
  );
}
