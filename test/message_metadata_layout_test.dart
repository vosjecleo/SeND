import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/message_metadata.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';

void main() {
  ChatMessage message({String body = 'hello', bool edited = true}) =>
      ChatMessage(
        id: 'm',
        sender: 'A',
        senderId: '@a:test',
        body: body,
        timestamp: DateTime(2026),
        pending: false,
        own: true,
        edited: edited,
      );
  testWidgets('placement uses rendered rich text, not a plain-body estimate', (
    tester,
  ) async {
    final m = message(body: 'long fallback ' * 80);
    late ReceiptPlacementScope scope;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: ReceiptPlacement(
                messages: [m],
                receiptIds: const {'m'},
                contentInset: 0,
                child: Builder(
                  builder: (context) {
                    scope = ReceiptPlacementScope.of(context)!;
                    return MatrixHtmlText(
                      html:
                          '<strong>Hi</strong> <span data-mx-spoiler="">secret</span>',
                      fallback: m.body,
                      trailing: messageMetadata(context, m, showReceipt: true),
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
    expect(scope.relocated, isEmpty);
    final body = tester.getRect(find.byType(SelectableText));
    final marker = tester.getRect(find.byIcon(Icons.check));
    expect(marker.bottom, lessThanOrEqualTo(body.bottom + 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('wide media keeps its width; marker moves to its own header', (
    tester,
  ) async {
    final m = message();
    late ReceiptPlacementScope scope;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 180,
              child: ReceiptPlacement(
                messages: [m],
                receiptIds: const {'m'},
                contentInset: 0,
                child: Builder(
                  builder: (context) {
                    scope = ReceiptPlacementScope.of(context)!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const HeaderMessageMetadata(messageId: 'm'),
                        MediaWithMessageMetadata(
                          message: m,
                          showReceipt: true,
                          child: const SizedBox(
                            key: Key('media'),
                            width: 180,
                            height: 100,
                          ),
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
    expect(tester.getSize(find.byKey(const Key('media'))).width, 180);
    expect(scope.relocated, {'m'});
    expect(scope.headers['m']!.single.id, 'm');
    expect(tester.takeException(), isNull);
  });
}
