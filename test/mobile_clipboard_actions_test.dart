import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets(
    'mobile selection toolbar copies, selects, cuts and pastes without losing focus',
    (tester) async {
      const keyboard = MethodChannel('net.deltie.deltiecord/composer');
      const geometry = EventChannel('net.deltie.deltiecord/keyboard_geometry');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        keyboard,
        (call) async => call.method == 'keyboardGeometry'
            ? {
                'visible': false,
                'physicalBottom': 0,
                'focused': true,
                'animating': false,
              }
            : null,
      );
      messenger.setMockStreamHandler(
        geometry,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(keyboard, null);
        messenger.setMockStreamHandler(geometry, null);
      });
      var clipboard = 'pasted';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboard.isNotEmpty};
          }
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = const [
          RoomSummary(
            id: '!clip:test',
            name: 'Clipboard test',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
            isDirect: true,
          ),
        ];
      await pumpMobile(tester, backend);
      await tester.tap(find.text('Clipboard test'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('mobile-composer-field'));
      await tester.enterText(field, 'hello world');
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final state = tester.state<EditableTextState>(editable);
      final controller = state.widget.controller;
      Future<void> action(ContextMenuButtonType type) async {
        state.showToolbar();
        await tester.pumpAndSettle();
        final toolbar = find.byType(AdaptiveTextSelectionToolbar);
        expect(toolbar, findsOneWidget);
        final label = switch (type) {
          ContextMenuButtonType.copy => 'Copy',
          ContextMenuButtonType.cut => 'Cut',
          ContextMenuButtonType.paste => 'Paste',
          ContextMenuButtonType.selectAll => 'Select all',
          _ => throw StateError('Unexpected toolbar action'),
        };
        final oldButton = tester.element(find.text(label).last);
        final tap = await tester.startGesture(
          tester.getCenter(find.text(label).last),
        );
        await tap.moveBy(const Offset(9, 1));
        backend.notifyListeners();
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          identical(oldButton, tester.element(find.text(label).last)),
          isTrue,
          reason: 'Sync updates must not replace a pressed toolbar button.',
        );
        await tap.up();
        await tester.pumpAndSettle();
      }

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await action(ContextMenuButtonType.copy);
      expect(clipboard, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 5);
      await action(ContextMenuButtonType.selectAll);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );
      await action(ContextMenuButtonType.cut);
      expect(controller.text, '');
      expect(clipboard, 'hello world');
      clipboard = 'new text';
      await action(ContextMenuButtonType.paste);
      expect(controller.text, 'new text');
      expect(state.widget.focusNode.hasFocus, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
