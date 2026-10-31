import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/mobile/mobile_timeline.dart';
import 'package:deltiecord/ui/plain_message_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

const _room = RoomSummary(
  id: 'room',
  name: 'Keyboard chat',
  lastMessage: '',
  unreadCount: 0,
  usesChannelIcon: false,
);

void main() {
  for (final tripleTap in [false, true]) {
    testWidgets('editing leaves the caret at the end, tripleTap=$tripleTap', (
      tester,
    ) async {
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..currentRoom = _room
        ..roomList = const [_room]
        ..messageList = [
          ChatMessage(
            id: 'edit',
            sender: 'Me',
            senderId: '@deltie:example.org',
            body: 'Keep this 👋',
            timestamp: DateTime(2026),
            pending: false,
            own: true,
          ),
        ];
      await tester.pumpWidget(DeltiecordApp(backend: backend));
      await tester.pumpAndSettle();
      final row = find.byKey(const Key('message-row-edit'));
      if (tripleTap) {
        for (var tap = 0; tap < 3; tap++) {
          await tester.tap(row);
          await tester.pump(const Duration(milliseconds: 50));
        }
      } else {
        await revealMessageActions(tester, row);
        await tester.tap(find.text('Edit'));
      }
      await tester.pumpAndSettle();
      final editor = tester.widget<PlainMessageEditor>(
        find.byType(PlainMessageEditor),
      );
      expect(editor.controller.document.toPlainText(), 'Keep this 👋\n');
      expect(editor.controller.selection.isCollapsed, isTrue);
      expect(editor.controller.selection.extentOffset, 'Keep this 👋'.length);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('plain-message-editor')),
      );
      expect(
        field.controller!.selection,
        TextSelection.collapsed(offset: field.controller!.text.length),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Editing message'), findsNothing);
      expect(field.controller!.text, isEmpty);
      expect(backend.sentMessages, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final mobile in [false, true]) {
    testWidgets(
      'arrows select the three emoji results and Tab inserts, mobile=$mobile',
      (tester) async {
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..currentRoom = _room
          ..roomList = const [_room]
          ..stickerPackList = [
            StickerPackSummary(
              id: 'p',
              name: 'Pack',
              stickers: [
                for (final name in ['qqa', 'qqb', 'qqc'])
                  StickerSummary(
                    id: name,
                    name: name,
                    mxcUri: Uri.parse('mxc://test/$name'),
                    assetType: StickerAssetType.emoji,
                  ),
              ],
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
          await tester.enterText(
            find.byKey(const ValueKey('mobile-composer-field')),
            ':qq',
          );
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
          await enterComposer(tester, ':qq');
          await tester.tap(find.byType(PlainMessageEditor));
        }
        await tester.pumpAndSettle();
        for (final key in [
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowUp,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final text = mobile
            ? tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('mobile-composer-field')),
                  )
                  .controller!
                  .text
            : tester
                  .widget<PlainMessageEditor>(find.byType(PlainMessageEditor))
                  .controller
                  .document
                  .toPlainText()
                  .trim();
        expect(text, ':qqb:');
        expect(backend.sentMessages, isEmpty);
        if (mobile) {
          await tester.enterText(
            find.byKey(const ValueKey('mobile-composer-field')),
            ':qq',
          );
        } else {
          await enterComposer(tester, ':qq');
        }
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        if (mobile) {
          // A key event does not synthesize the Android IME's editing update.
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('mobile-composer-field')),
                )
                .controller!
                .text,
            ':qq',
          );
          expect(backend.sentMessages, isEmpty);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: ':qq\n',
              selection: TextSelection.collapsed(offset: 4),
            ),
          );
          await tester.pump();
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('mobile-composer-field')),
                )
                .controller!
                .text,
            ':qq\n',
          );
        } else {
          expect(backend.sentMessages, [':qq']);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final ctrl in [false, true]) {
    testWidgets(
      'voice text on desktop honours Enter/Shift/Ctrl, ctrlPreference=$ctrl',
      (tester) async {
        const voice = RoomSummary(
          id: 'voice',
          name: 'Voice chat',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        );
        final backend = FakeBackend()
          ..currentRoom = voice
          ..currentPreferences = AppPreferences(sendWithCtrlEnter: ctrl);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
            ),
            home: Scaffold(
              body: MobileTimelineView(
                navigationGestureActive: false,
                initialDraft: '',
                initialCustomEmojis: const [],
                onDraftChanged: (_) {},
                backend: backend,
                room: voice,
                desktopKeyboard: true,
                onOpenNavigation: () {},
                onOpenDetails: () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('mobile-composer-field'));
        await tester.enterText(field, 'Hello voice');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(backend.sentMessages, isEmpty);
        await tester.enterText(field, 'Hello voice');
        if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(backend.sentMessages, ['Hello voice']);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
