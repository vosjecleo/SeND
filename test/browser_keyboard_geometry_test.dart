@TestOn('browser')
library;

import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/browser_lifecycle.dart' as browser;
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/mobile/mobile_chat_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

@JS('Object.defineProperty')
external JSObject _define(JSObject target, JSString key, JSAny descriptor);
@JS('Reflect.deleteProperty')
external JSBoolean _delete(JSObject target, JSString key);

void main() {
  test('browser tests/older hosts tolerate an absent geometry bridge', () {
    expect(browser.browserKeyboardGeometry, isNull);
  });

  testWidgets(
    'PWA return repairs stale space without replacing the editor or draft',
    (tester) async {
      var geometry = <String, Object?>{
        'visible': false,
        'physicalBottom': 0,
        'physicalViewportHeight': 900,
        'focused': true,
        'animating': false,
      };
      final read = (() => geometry.jsify() as JSObject).toJS;
      _define(
        web.window,
        'sendKeyboardGeometry'.toJS,
        {'value': read, 'configurable': true}.jsify()!,
      );
      void visibility(bool visible) {
        _define(
          web.document,
          'hidden'.toJS,
          {'value': !visible, 'configurable': true}.jsify()!,
        );
        _define(
          web.document,
          'visibilityState'.toJS,
          {
            'value': visible ? 'visible' : 'hidden',
            'configurable': true,
          }.jsify()!,
        );
        web.document.dispatchEvent(web.Event('visibilitychange'));
      }

      addTearDown(() {
        _delete(web.window, 'sendKeyboardGeometry'.toJS);
        _delete(web.document, 'hidden'.toJS);
        _delete(web.document, 'visibilityState'.toJS);
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      visibility(true);
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
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: MobileChatShell(backend: backend),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      final composer = find.byKey(const ValueKey('mobile-composer-field'));
      await tester.enterText(composer, 'Browser draft');
      final focus = tester.widget<TextField>(composer).focusNode!;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      geometry = {
        ...geometry,
        'visible': true,
        'physicalBottom': 300,
        'physicalViewportHeight': 600,
      };
      web.window.dispatchEvent(web.Event('send-keyboard-geometry'));
      await tester.pump();
      await tester.pumpAndSettle();
      final raised = tester.getBottomLeft(composer).dy;
      expect(focus.hasFocus, isTrue, reason: 'before background');
      visibility(false);
      await tester.pump();
      geometry = {
        ...geometry,
        'visible': false,
        'physicalBottom': 0,
        'physicalViewportHeight': 900,
      };
      visibility(true);
      await tester.pumpAndSettle();
      // Browser input policies can refuse an automatic reopen. In that case
      // the same editor must remain and the keyboard-sized gap must be gone.
      expect(tester.widget<TextField>(composer).focusNode, same(focus));
      expect(find.text('Browser draft'), findsOneWidget);
      expect(tester.getBottomLeft(composer).dy, greaterThan(raised + 200));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
