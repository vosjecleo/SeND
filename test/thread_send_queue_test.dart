import 'dart:async';
import 'package:deltiecord/backend/thread_session.dart';
import 'package:deltiecord/backend/conversation_send_target.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/queued_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _Thread extends ThreadSession {
  _Thread(this.rootId, this.sent);
  @override
  final String rootId;
  final List<String> sent;
  void Function()? onSend;
  @override
  String get roomId => 'room';
  @override
  List<ChatMessage> get messages => [];
  @override
  bool get loading => false;
  @override
  bool get canLoadMore => false;
  @override
  String? get error => null;
  @override
  Future<void> loadMore() async {}
  @override
  Future<void> send(
    String text, {
    String? formattedBody,
    String? editMessageId,
    String? replyToMessageId,
  }) async {
    sent.add('$rootId:$text');
    onSend?.call();
  }

  @override
  Future<void> attach(
    AttachmentDraft draft, {
    String? replyToMessageId,
  }) async => sent.add('$rootId:${draft.name}');
  @override
  ConversationSendTarget get sendTarget => ConversationSendTarget(
    roomId: roomId,
    threadRootId: rootId,
    send: send,
    attach: attach,
  );
}

class _ReconciledBackend extends FakeBackend {
  @override
  bool get reconcilesOutgoingTransactions => true;
}

void main() {
  test(
    'closed conversations reconcile sync arriving before or after completion',
    () async {
      final backend = _ReconciledBackend(), thread = _Thread('closed', []);
      thread.onSend = () =>
          backend.acknowledgeQueuedTransactions([queuedTransactionId!]);
      for (var i = 0; i < 60; i++) {
        await backend.submitComposerMessage(
          roomId: 'room',
          text: 'message$i',
          thread: thread,
        );
      }
      expect(
        backend.conversationMessages(
          roomId: 'room',
          sent: [],
          threadRootId: 'closed',
        ),
        isEmpty,
      );
      thread.onSend = null;
      await backend.submitComposerMessage(
        roomId: 'room',
        text: 'late ack',
        thread: thread,
      );
      final pending = backend.conversationMessages(
        roomId: 'room',
        sent: [],
        threadRootId: 'closed',
      );
      expect(pending.length, 1);
      backend.acknowledgeQueuedTransactions([pending.single.id]);
      expect(
        backend.conversationMessages(
          roomId: 'room',
          sent: [],
          threadRootId: 'closed',
        ),
        isEmpty,
      );
      backend.dispose();
      thread.dispose();
    },
  );
  test('thread outbox is scoped and survives closing its view', () async {
    final backend = FakeBackend();
    final sent = <String>[];
    final one = _Thread('one', sent), two = _Thread('two', sent);
    final gate = Completer<void>();
    final blocker = backend.enqueueRoomSend('room', () => gate.future);
    final first = backend.submitComposerMessage(
      roomId: 'room',
      text: 'first',
      thread: one,
    );
    final second = backend.submitComposerMessage(
      roomId: 'room',
      text: 'second',
      thread: two,
    );
    expect(
      backend
          .conversationMessages(roomId: 'room', sent: [], threadRootId: 'one')
          .single
          .body,
      'first',
    );
    expect(
      backend
          .conversationMessages(roomId: 'room', sent: [], threadRootId: 'two')
          .single
          .body,
      'second',
    );
    expect(backend.conversationMessages(roomId: 'room', sent: []), isEmpty);
    one.dispose();
    two.dispose();
    gate.complete();
    await Future.wait([blocker, first, second]);
    expect(sent, ['one:first', 'two:second']);
    backend.dispose();
  });
  test('wrong room and author-only edit checks run before queueing', () async {
    final backend = FakeBackend(), thread = _Thread('one', []);
    await expectLater(
      backend.submitComposerMessage(
        roomId: 'other',
        text: 'oops',
        thread: thread,
      ),
      throwsStateError,
    );
    await expectLater(
      backend.submitComposerMessage(
        roomId: 'room',
        text: 'oops',
        thread: thread,
        editMessageId: 'foreign',
      ),
      throwsStateError,
    );
    backend.dispose();
    thread.dispose();
  });
}
