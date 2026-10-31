import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/message_metadata.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';

void main() {
  testWidgets(
    'receipts, pins and bookmarks do not move the following message down',
    (tester) async {
      for (final scale in [1.0, 1.5]) {
        Future<void> show({required bool markers}) => tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 300,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (context) => TrailingMessageMetadata(
                            metadata: markers
                                ? messageMetadata(
                                    context,
                                    ChatMessage(
                                      id: 'pin',
                                      sender: 'Me',
                                      body: 'Hi',
                                      timestamp: DateTime(2026),
                                      pending: false,
                                      pinned: true,
                                      bookmarked: true,
                                    ),
                                    showReceipt: true,
                                  )
                                : null,
                            child: const Text(
                              'Hi',
                              style: TextStyle(fontSize: 12, height: 1),
                            ),
                          ),
                        ),
                        const Text('Next message', key: Key('next-message')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await show(markers: false);
        final before = tester
            .getTopLeft(find.byKey(const Key('next-message')))
            .dy;
        await show(markers: true);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(const Key('next-message'))).dy,
          closeTo(before, .01),
        );
        final pin = tester.widget<Icon>(find.byIcon(Icons.push_pin));
        final receipt = tester.widget<Icon>(find.byIcon(Icons.check));
        expect(pin.color, receipt.color);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.bookmark)).color,
          pin.color,
        );
        expect(
          tester.getRect(find.byIcon(Icons.push_pin)).right,
          lessThanOrEqualTo(tester.getRect(find.byIcon(Icons.bookmark)).left),
        );
        expect(
          tester.getRect(find.byIcon(Icons.bookmark)).right,
          lessThanOrEqualTo(tester.getRect(find.byIcon(Icons.check)).left),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('pinned media shows its pin without requiring a receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaWithMessageMetadata(
            message: ChatMessage(
              id: 'p',
              sender: 'A',
              body: '',
              timestamp: DateTime(2026),
              pending: false,
              pinned: true,
            ),
            showReceipt: false,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Pinned message'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });
  testWidgets('bookmarked media shows its bookmark without a pin or receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaWithMessageMetadata(
            message: ChatMessage(
              id: 'b',
              sender: 'A',
              body: '',
              timestamp: DateTime(2026),
              pending: false,
              bookmarked: true,
            ),
            showReceipt: false,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Bookmarked message'), findsOneWidget);
    expect(find.byTooltip('Pinned message'), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });
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

  testWidgets(
    'media receipt stays immediately right of media, not in a new row',
    (tester) async {
      final message = ChatMessage(
        id: 'media',
        sender: 'Me',
        body: '',
        timestamp: DateTime(2026),
        own: true,
        pending: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MediaWithMessageMetadata(
                message: message,
                showReceipt: true,
                child: const SizedBox(
                  key: Key('image'),
                  width: 100,
                  height: 80,
                ),
              ),
            ),
          ),
        ),
      );
      final media = tester.getRect(find.byKey(const Key('image')));
      final receipt = tester.getRect(find.byIcon(Icons.check));
      expect(receipt.left, greaterThan(media.right));
      expect(receipt.left - media.right, lessThan(12));
      expect(receipt.bottom, lessThanOrEqualTo(media.bottom));
      expect(tester.widget<Icon>(find.byIcon(Icons.check)).size, 10);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
}
