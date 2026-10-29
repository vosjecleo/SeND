import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/attachment_admission.dart';
import 'package:deltiecord/ui/plain_message_editor.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _BudgetBackend extends FakeBackend {
  @override
  Future<List<AttachmentDraft>> prepareAttachmentsForSend(
    List<AttachmentDraft> drafts, {
    void Function(int index, String status, double? progress)? onProgress,
  }) async => throw AttachmentBudgetExceeded(drafts);
}

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'oversized upload retains the text and marked attachment before any upload, mobile=$mobile',
      (tester) async {
        const room = RoomSummary(
          id: '!r:test',
          name: 'Attachments',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        );
        final backend = _BudgetBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = [room];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
        }
        await tester.tap(find.text('Attachments'));
        await tester.pumpAndSettle();
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/hK0P7wAAAABJRU5ErkJggg==',
        );
        final draft = AttachmentDraft(
          bytes: bytes,
          name: 'photo.png',
          mimeType: 'image/png',
          spoiler: false,
        );
        if (mobile) {
          final field = tester.widget<TextField>(
            find.byKey(const ValueKey('mobile-composer-field')),
          );
          field.contentInsertionConfiguration!.onContentInserted(
            KeyboardInsertedContent(
              mimeType: draft.mimeType,
              uri: '',
              data: bytes,
            ),
          );
          await tester.enterText(
            find.byKey(const ValueKey('mobile-composer-field')),
            'caption',
          );
        } else {
          final dynamic conversation = tester.widget(
            find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_Conversation',
            ),
          );
          conversation.onDropAttachments([draft]);
          await enterComposer(tester, 'caption');
        }
        await tester.pumpAndSettle();
        await tester.tap(
          mobile ? find.byIcon(Icons.send).last : find.byTooltip('Send'),
        );
        await tester.pumpAndSettle();
        expect(backend.sentAttachmentRoomIds, isEmpty);
        expect(find.byIcon(Icons.error), findsOneWidget);
        expect(
          find.textContaining('Uh-oh! Your attachment is too big.'),
          findsOneWidget,
        );
        final text = mobile
            ? tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('mobile-composer-field')),
                  )
                  .controller!
                  .text
            : tester
                  .widget<PlainMessageEditor>(find.byType(PlainMessageEditor))
                  .controller
                  .document
                  .toPlainText()
                  .trim();
        expect(text, 'caption');
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
