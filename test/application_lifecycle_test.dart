import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('phone gesture can lose focus without hiding the app surface', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await pumpMobile(tester, backend);
    final lifecycle =
        tester.state(find.byType(ApplicationLifecycle))
            as WidgetsBindingObserver;
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    lifecycle.didChangeViewFocus(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.unfocused,
        direction: ViewFocusDirection.forward,
      ),
    );
    await tester.pump();
    expect(backend.activitySurfaceStates.last, isTrue);
    expect(backend.applicationForegroundStates.last, isFalse);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(backend.activitySurfaceStates.last, isFalse);

    final refreshes = backend.applicationRefreshCount;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(backend.activitySurfaceStates.last, isTrue);
    expect(backend.applicationForegroundStates.last, isFalse);
    expect(backend.applicationRefreshCount, greaterThan(refreshes));
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  });

  testWidgets(
    'an unfocused visible surface still refreshes activity but not receipts',
    (tester) async {
      final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
      await tester.pumpWidget(
        DeltiecordApp(backend: backend, platformOverride: TargetPlatform.linux),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      (tester.state(find.byType(ApplicationLifecycle))
              as WidgetsBindingObserver)
          .didChangeViewFocus(
            ViewFocusEvent(
              viewId: tester.view.viewId,
              state: ViewFocusState.unfocused,
              direction: ViewFocusDirection.forward,
            ),
          );
      await tester.pump();
      expect(backend.applicationForegroundStates.last, isFalse);
      expect(backend.activitySurfaceStates.last, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(backend.activitySurfaceStates.last, isFalse);
      await tester.pumpWidget(const SizedBox());
      backend.dispose();
    },
  );
  testWidgets('read receipts require a foreground visible conversation', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!receipt:test',
          name: 'Receipt test',
          lastMessage: 'hello',
          unreadCount: 1,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    await pumpMobile(tester, backend);

    expect(backend.applicationForegroundStates.last, isTrue);
    expect(backend.conversationVisibilityStates.last, isFalse);

    await tester.tap(find.text('Receipt test'));
    await tester.pumpAndSettle();
    expect(backend.conversationVisibilityStates.last, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(backend.applicationForegroundStates.last, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(backend.applicationForegroundStates.last, isTrue);

    await tester.tap(find.byKey(const ValueKey('mobile-open-navigation')));
    await tester.pumpAndSettle();
    expect(backend.conversationVisibilityStates.last, isFalse);
  });

  testWidgets(
    'IME language chooser keeps the composer focused while inactive',
    (tester) async {
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = const [
          RoomSummary(
            id: '!ime',
            name: 'IME chat',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
            isDirect: true,
          ),
        ];
      await pumpMobile(tester, backend);
      await tester.tap(find.text('IME chat'));
      await tester.pumpAndSettle();
      final editable = find.byType(EditableText).hitTestable().first;
      await tester.tap(editable);
      await tester.pump();
      final focus = tester.widget<EditableText>(editable).focusNode;
      expect(focus.hasFocus, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
    },
  );
}
