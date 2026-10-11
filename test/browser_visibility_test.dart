@TestOn('browser')
library;

import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'widget_test.dart' show FakeBackend;

@JS('Object.defineProperty')
external JSObject _define(JSObject target, JSString key, JSAny descriptor);
@JS('Reflect.deleteProperty')
external JSBoolean _delete(JSObject target, JSString key);

class _Backend extends FakeBackend {
  final visible = <bool>[];
  @override
  void setApplicationForeground(bool value) => visible.add(value);
}

void main() {
  testWidgets(
    'page visibility backgrounds the backend without waiting for Flutter lifecycle',
    (tester) async {
      final backend = _Backend()..currentStatus = SessionStatus.signedIn;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
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
        _delete(web.document, 'hidden'.toJS);
        _delete(web.document, 'visibilityState'.toJS);
      });
      visibility(true);
      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationLifecycle(backend: backend, child: const SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(backend.visible.last, isTrue);
      visibility(false);
      await tester.pump();
      expect(backend.visible.last, isFalse);
      visibility(true);
      await tester.pump();
      expect(backend.visible.last, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
