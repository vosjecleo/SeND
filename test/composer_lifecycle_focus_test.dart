import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show FakeBackend;

void main() {
  testWidgets(
    'mobile composer keeps focus and draft through IME lifecycle round trip',
    (tester) async {
      const channel = MethodChannel('net.deltie.deltiecord/composer');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => true,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
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
      await tester.pump(const Duration(milliseconds: 250));
      expect(focus.hasFocus, isTrue);
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
  testWidgets(
    'resume clears stale insets only when Android reports keyboard hidden',
    (tester) async {
      const channel = MethodChannel('net.deltie.deltiecord/composer');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => false,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
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
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      final raised = tester.getBottomLeft(composer).dy;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(tester.getBottomLeft(composer).dy, greaterThan(raised + 200));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
