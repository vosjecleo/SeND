import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/mobile/mobile_chat_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _KeyboardFeed {
  static const methods = MethodChannel('net.deltie.deltiecord/composer');
  static const events = EventChannel('net.deltie.deltiecord/keyboard_geometry');
  MockStreamHandlerEventSink? sink;
  Map<String, Object?> state = {
    'visible': false,
    'physicalBottom': 0.0,
    'focused': true,
    'animating': false,
  };
  void install(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      methods,
      (call) async => call.method == 'keyboardGeometry' ? state : null,
    );
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, events) {
          sink = events;
          events.success(state);
        },
        onCancel: (_) {
          sink = null;
        },
      ),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockStreamHandler(events, null);
    });
  }

  void emit({
    required bool? visible,
    double bottom = 0,
    bool focused = true,
    bool animating = false,
    int? subtype,
  }) {
    state = {
      'visible': visible,
      'physicalBottom': bottom,
      'focused': focused,
      'animating': animating,
      'inputSubtype': subtype,
    };
    sink?.success(state);
  }
}

Future<Finder> _openComposer(
  WidgetTester tester,
  _KeyboardFeed keyboard, {
  double scale = 1,
}) async {
  keyboard.install(tester);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  final backend = FakeBackend()
    ..currentStatus = SessionStatus.signedIn
    ..currentPreferences = AppPreferences(interfaceScale: scale)
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
    DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alice'));
  await tester.pumpAndSettle();
  final composer = find.byKey(const ValueKey('mobile-composer-field'));
  await tester.enterText(composer, 'Keep this draft');
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  keyboard.emit(visible: true, bottom: 300);
  await tester.pump();
  await tester.pumpAndSettle();
  expect(keyboard.sink, isNotNull);
  return composer;
}

void _lifecycle(WidgetTester tester, Iterable<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _viewFocus(WidgetTester tester, ViewFocusState state) =>
    // Exercise the shell observer without desktop-style view focus traversal.
    // Android's IME window changes do not tab to the first control in the app.
    (tester.state(find.byType(MobileChatShell)) as WidgetsBindingObserver)
        .didChangeViewFocus(
          ViewFocusEvent(
            viewId: tester.view.viewId,
            state: state,
            direction: ViewFocusDirection.forward,
          ),
        );
const _background = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const _resume = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];
Iterable<MethodCall> _keyboardCommands(WidgetTester tester) =>
    tester.testTextInput.log.where(
      (call) =>
          call.method == 'TextInput.hide' || call.method == 'TextInput.show',
    );

void main() {
  testWidgets(
    'timeline swipe opens Home after keyboard closes with focus retained',
    (tester) async {
      final keyboard = _KeyboardFeed();
      final composer = await _openComposer(tester, keyboard);
      keyboard.emit(visible: false);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isTrue);
      await tester.dragFrom(const Offset(110, 300), const Offset(270, 0));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Keep this draft'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'language subtype change restores a dismissed IME once without hiding it',
    (tester) async {
      final keyboard = _KeyboardFeed();
      final composer = await _openComposer(tester, keyboard);
      keyboard.emit(visible: true, bottom: 300, subtype: 1);
      await tester.pump();
      tester.testTextInput.log.clear();
      _viewFocus(tester, ViewFocusState.unfocused);
      keyboard.emit(visible: null, focused: false, subtype: 1);
      await tester.pump();
      _viewFocus(tester, ViewFocusState.focused);
      keyboard.emit(visible: false, subtype: 2);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      await tester.pump();
      expect(
        _keyboardCommands(tester).where((c) => c.method == 'TextInput.hide'),
        isEmpty,
      );
      expect(
        _keyboardCommands(
          tester,
        ).where((c) => c.method == 'TextInput.show').length,
        lessThanOrEqualTo(1),
      );
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Keep this draft',
      );
      keyboard.emit(visible: true, bottom: 300, subtype: 2);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TextField>(composer).focusNode!.hasFocus, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Gboard-style focus-only picker never hides or reopens IME', (
    tester,
  ) async {
    final keyboard = _KeyboardFeed();
    final composer = await _openComposer(tester, keyboard);
    final field = tester.widget<TextField>(composer);
    final focus = field.focusNode!;
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Keep this draft',
        selection: TextSelection.collapsed(offset: 15),
        composing: TextRange(start: 10, end: 15),
      ),
    );
    await tester.pump();
    tester.testTextInput.log.clear();
    for (var i = 0; i < 3; i++) {
      _lifecycle(tester, [AppLifecycleState.inactive]);
      _viewFocus(tester, ViewFocusState.unfocused);
      keyboard.emit(visible: null, focused: false);
      await tester.pump(const Duration(seconds: 1));
      _viewFocus(tester, ViewFocusState.focused);
      _lifecycle(tester, [AppLifecycleState.resumed]);
      keyboard.emit(visible: false, animating: true);
      await tester.pump();
      keyboard.emit(visible: true, bottom: 300);
      await tester.pump(const Duration(seconds: 2));
      expect(focus.hasFocus, isTrue);
      expect(field.controller!.text, 'Keep this draft');
      expect(
        field.controller!.value.composing,
        const TextRange(start: 10, end: 15),
      );
      expect(_keyboardCommands(tester), isEmpty);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'real resume keeps the draft and does not reopen an already visible IME',
    (tester) async {
      final keyboard = _KeyboardFeed();
      final composer = await _openComposer(tester, keyboard);
      final focus = tester.widget<TextField>(composer).focusNode!;
      tester.testTextInput.log.clear();
      _lifecycle(tester, _background);
      await tester.pump();
      _lifecycle(tester, _resume);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(_keyboardCommands(tester), isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      // Deliberate dismissal must still work.
      focus.unfocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('declined restore lowers stale layout without dropping focus', (
    tester,
  ) async {
    final keyboard = _KeyboardFeed();
    final composer = await _openComposer(tester, keyboard);
    final focus = tester.widget<TextField>(composer).focusNode!;
    final raised = tester.getBottomLeft(composer).dy;
    tester.testTextInput.log.clear();
    _lifecycle(tester, _background);
    keyboard.emit(visible: false);
    await tester.pump();
    _lifecycle(tester, _resume);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(tester.getBottomLeft(composer).dy, greaterThan(raised + 200));
    expect(
      _keyboardCommands(
        tester,
      ).where((c) => c.method == 'TextInput.show').length,
      1,
    );
    expect(
      _keyboardCommands(tester).where((c) => c.method == 'TextInput.hide'),
      isEmpty,
    );
    tester.testTextInput.log.clear();
    await tester.pump(const Duration(seconds: 3));
    keyboard.emit(visible: false);
    await tester.pumpAndSettle();
    expect(
      _keyboardCommands(tester),
      isEmpty,
      reason: 'No retry/show/hide loop',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'late geometry still repairs the layout after a touch cancels reopen',
    (tester) async {
      final keyboard = _KeyboardFeed();
      final composer = await _openComposer(tester, keyboard);
      final raised = tester.getBottomLeft(composer).dy;
      _lifecycle(tester, _background);
      keyboard.emit(visible: null, focused: false);
      await tester.pump();
      _lifecycle(tester, _resume);
      await tester.pump();
      await tester.tap(composer);
      await tester.pump();
      tester.testTextInput.log.clear();
      keyboard.emit(visible: false);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(composer).dy, greaterThan(raised + 200));
      expect(_keyboardCommands(tester), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'manual dismissal stays closed and fresh geometry can reopen the layout',
    (tester) async {
      final keyboard = _KeyboardFeed();
      final composer = await _openComposer(tester, keyboard);
      final focus = tester.widget<TextField>(composer).focusNode!;
      tester.testTextInput.log.clear();
      keyboard.emit(visible: false);
      await tester.pump();
      await tester.pumpAndSettle();
      final lowered = tester.getBottomLeft(composer).dy;
      await tester.pump(const Duration(seconds: 2));
      expect(_keyboardCommands(tester), isEmpty);
      keyboard.emit(visible: true, bottom: 300);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(composer).dy, lessThan(lowered - 200));
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('geometry repair retains the phone navigation safe area', (
    tester,
  ) async {
    final keyboard = _KeyboardFeed();
    final composer = await _openComposer(tester, keyboard);
    tester.view.viewPadding = const FakeViewPadding(bottom: 30);
    addTearDown(tester.view.resetViewPadding);
    _lifecycle(tester, _background);
    keyboard.emit(visible: false);
    await tester.pump();
    _lifecycle(tester, _resume);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(composer).dy, lessThanOrEqualTo(870));
    expect(tester.getBottomLeft(composer).dy, greaterThan(800));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('resumed geometry respects the app interface scale', (
    tester,
  ) async {
    final keyboard = _KeyboardFeed();
    final composer = await _openComposer(tester, keyboard, scale: 1.25);
    final raised = tester.getBottomLeft(composer).dy;
    _lifecycle(tester, _background);
    keyboard.emit(visible: false);
    await tester.pump();
    _lifecycle(tester, _resume);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(composer).dy, greaterThan(raised + 200));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'OS-parking focus before background does not lose the saved editor',
    (tester) async {
      final keyboard = _KeyboardFeed();
      final composer = await _openComposer(tester, keyboard);
      final focus = tester.widget<TextField>(composer).focusNode!;
      _lifecycle(tester, [AppLifecycleState.inactive]);
      FocusManager.instance.rootScope.requestScopeFocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      _lifecycle(tester, [AppLifecycleState.hidden, AppLifecycleState.paused]);
      keyboard.emit(visible: false);
      await tester.pump();
      _lifecycle(tester, _resume);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(find.text('Keep this draft'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
