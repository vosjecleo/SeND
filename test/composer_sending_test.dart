import 'package:deltiecord/ui/plain_message_editor.dart';
import 'dart:async';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets(
    'attachment drag rejects browser text and clears on cancellation',
    (tester) async {
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = const [
          RoomSummary(
            id: '!room:test',
            name: 'Chat',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          ),
        ];
      await backend.selectRoom('!room:test');
      await tester.pumpWidget(DeltiecordApp(backend: backend));
      await tester.pumpAndSettle();
      final region = tester.widget<DropRegion>(find.byType(DropRegion));
      final browser = TestDropSession([
        Formats.plainText,
        Formats.htmlText,
        Formats.htmlFile,
        Formats.uri,
      ]);
      DropOverEvent over(DropSession session) => DropOverEvent(
        session: session,
        position: DropPosition(local: Offset.zero, global: Offset.zero),
      );
      expect(await region.onDropOver(over(browser)), DropOperation.none);
      final image = TestDropSession([Formats.png]);
      expect(await region.onDropOver(over(image)), DropOperation.copy);
      await tester.pump();
      expect(find.text('Drop files to attach'), findsOneWidget);
      image.ended.notifyListeners();
      await tester.pump();
      expect(find.text('Drop files to attach'), findsNothing);
    },
  );

  testWidgets('sends composer text and clears it after success', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'No messages yet',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    final composer = tester.widget<PlainMessageEditor>(
      find.byType(PlainMessageEditor),
    );
    expect(composer.focusNode.hasFocus, isTrue);
    await enterComposer(tester, 'hello from SeND');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(backend.sentMessages, ['hello from SeND']);
    expect(find.text('hello from SeND'), findsNothing);
    expect(composer.focusNode.hasFocus, isTrue);
  });

  testWidgets('typing during an in-flight send preserves the next draft', (
    tester,
  ) async {
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..sendGate = gate
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    await enterComposer(tester, 'first message');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    await enterComposer(tester, 'next draft typed immediately');
    gate.complete();
    await tester.pumpAndSettle();

    final editor = tester.widget<PlainMessageEditor>(
      find.byType(PlainMessageEditor),
    );
    expect(backend.sentMessages, ['first message']);
    expect(
      editor.controller.document.toPlainText(),
      'next draft typed immediately\n',
    );
  });

  testWidgets('an in-flight send keeps its original target room', (
    tester,
  ) async {
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..sendGate = gate
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!two:example.org',
          name: 'two',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('one'));
    await tester.pump();
    await enterComposer(tester, 'keep this in room one');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.tap(find.text('two'));
    await tester.pump();

    expect(backend.sentMessageRoomIds, ['!one:example.org']);
    gate.complete();
    await tester.pump();
  });

  testWidgets('autocompletes Matrix user mentions into the composer', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..mentionList = const [
        MentionSuggestion(matrixId: '@alice:example.org', displayName: 'Alice'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    await enterComposer(tester, '@ali');

    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Alice').last);
    await tester.pump();
    final editor = tester.widget<PlainMessageEditor>(
      find.byType(PlainMessageEditor),
    );
    expect(editor.controller.document.toPlainText(), '@alice:example.org \n');
  });

  testWidgets('autocompletes room links with a readable room name', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..mentionList = const [
        MentionSuggestion(
          matrixId: '!general:example.org',
          displayName: 'general',
          isRoom: true,
        ),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    await enterComposer(tester, '@gen');

    expect(find.text('Room'), findsOneWidget);
    await tester.tap(find.text('general').last);
    await tester.pump();
    final editor = tester.widget<PlainMessageEditor>(
      find.byType(PlainMessageEditor),
    );
    expect(editor.controller.document.toPlainText(), '#general \n');
  });

  testWidgets('restores independent composer drafts while switching rooms', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!two:example.org',
          name: 'two',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('one'));
    await tester.pump();
    await enterComposer(tester, 'draft one');

    await tester.tap(find.text('two'));
    await tester.pump();
    expect(
      tester
          .widget<PlainMessageEditor>(find.byType(PlainMessageEditor))
          .controller
          .document
          .toPlainText(),
      '\n',
    );
    await enterComposer(tester, 'draft two');

    await tester.tap(find.text('one'));
    await tester.pump();
    expect(
      tester
          .widget<PlainMessageEditor>(find.byType(PlainMessageEditor))
          .controller
          .document
          .toPlainText(),
      'draft one\n',
    );
  });

  testWidgets('multiline composer grows but remains within lower third', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!multiline:example.org',
          name: 'multiline',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('multiline'));
    await tester.pumpAndSettle();

    final composerPanel = find.byKey(const Key('message-composer-panel'));
    final initialHeight = tester.getSize(composerPanel).height;
    await enterComposer(
      tester,
      List.generate(12, (index) => 'Line ${index + 1}').join('\n'),
    );
    await tester.pumpAndSettle();

    final expandedHeight = tester.getSize(composerPanel).height;
    expect(expandedHeight, greaterThan(initialHeight));
    expect(expandedHeight, lessThanOrEqualTo((900 - 56) / 3 + 0.1));
  });

  testWidgets(
    'desktop composer grows on soft wrap without stretching user island',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const room = RoomSummary(
        id: '!test:example.org',
        name: 'Test',
        lastMessage: '',
        unreadCount: 0,
        usesChannelIcon: false,
      );
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = [room]
        ..currentRoom = room;
      await tester.pumpWidget(
        DeltiecordApp(backend: backend, platformOverride: TargetPlatform.linux),
      );
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('message-composer-island'));
      final user = find.byKey(const Key('current-user-island'));
      final initialHeight = tester.getSize(composer).height;
      final userHeight = tester.getSize(user).height;
      tester
          .widget<PlainMessageEditor>(find.byType(PlainMessageEditor))
          .controller
          .replaceText(0, 0, 'a long wrapping message ' * 30, null);
      await tester.pumpAndSettle();
      expect(tester.getSize(composer).height, greaterThan(initialHeight));
      expect(tester.getSize(user).height, userHeight);
      expect(tester.takeException(), isNull);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
}
