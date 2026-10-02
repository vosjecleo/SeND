import 'package:deltiecord/ui/call_and_chat_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat remains mounted and below the call when joining/leaving', (
    tester,
  ) async {
    var calling = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: CallAndChatLayout(
                call: calling
                    ? const ColoredBox(key: Key('call'), color: Colors.blue)
                    : null,
                chat: const TextField(key: Key('chat')),
              ),
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('chat')), 'Unsent draft');
    final state = tester.state(find.byType(EditableText));
    rebuild(() => calling = true);
    await tester.pump();
    expect(tester.state(find.byType(EditableText)), same(state));
    expect(find.text('Unsent draft'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('chat'))).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const Key('call'))).dy,
      ),
    );
    rebuild(() => calling = false);
    await tester.pump();
    expect(tester.state(find.byType(EditableText)), same(state));
    expect(find.text('Unsent draft'), findsOneWidget);
  });

  testWidgets('keyboard-sized viewport prioritizes chat without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 280,
            child: CallAndChatLayout(
              call: Text('Call stage'),
              chat: TextField(),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Call stage'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
