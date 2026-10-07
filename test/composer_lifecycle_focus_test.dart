import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show FakeBackend;

void main() {
  testWidgets(
    'mobile composer keeps focus and draft through IME lifecycle round trip',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = const [
          RoomSummary(
            id: '!room:test',
            name: 'Alice',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          ),
        ];
      await tester.pumpWidget(
        DeltiecordApp(
          backend: backend,
          platformOverride: TargetPlatform.android,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      final composer = find.byKey(const ValueKey('mobile-composer-field'));
      await tester.enterText(composer, 'Keep this draft');
      final focus = tester.widget<TextField>(composer).focusNode!;
      expect(focus.hasFocus, isTrue);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        expect(
          focus.hasFocus,
          isTrue,
          reason: '$state must not discard composer focus',
        );
      }
      expect(find.text('Keep this draft'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(find.text('Keep this draft'), findsOneWidget);
      // Deliberate dismissal must still work; no automatic refocus loop.
      focus.unfocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
