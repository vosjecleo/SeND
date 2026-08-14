import 'dart:typed_data';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/backend/chat_backend.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows login controls when signed out', (tester) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('Deltiecord'), findsOneWidget);
    expect(find.text('Homeserver'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('shows joined rooms and opens a timeline', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello there',
          unreadCount: 2,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('general'), findsOneWidget);
    await tester.tap(find.text('general'));
    await tester.pump();

    expect(backend.selectedRoom?.id, '!general:example.org');
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('selects a Matrix Space from the server bar', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie Club'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.byTooltip('Deltie Club'), findsOneWidget);
    await tester.tap(find.byTooltip('Deltie Club'));
    await tester.pump();

    expect(backend.selectedSpaceId, '!space:example.org');
    expect(find.text('Deltie Club'), findsOneWidget);
  });

  testWidgets('opens voice rooms without exposing a message composer', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!voice:example.org',
          name: 'Lounge',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Lounge'));
    await tester.pump();

    expect(find.text('VOICE ROOMS'), findsOneWidget);
    expect(find.text('Nobody is connected'), findsOneWidget);
    expect(find.byType(QuillEditor), findsNothing);
  });

  testWidgets('prompts an unverified device for recovery', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..security = const EncryptionSetupState(
        status: EncryptionSetupStatus.needsRecovery,
        keyBackupEnabled: true,
        crossSigningEnabled: true,
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('Fix encryption'), findsOneWidget);
    await tester.tap(find.text('Fix encryption'));
    await tester.pumpAndSettle();

    expect(find.text('Recovery required'), findsOneWidget);
    expect(find.text('Recover & verify'), findsOneWidget);
    expect(find.text('Encrypted key backup'), findsOneWidget);
  });

  testWidgets('requires saving a newly generated recovery key', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..security = const EncryptionSetupState(
        status: EncryptionSetupStatus.needsSetup,
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Fix encryption'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up encryption'));
    await tester.pumpAndSettle();

    expect(find.text('recovery-key'), findsOneWidget);
    expect(
      find.text('I saved this recovery key somewhere safe'),
      findsOneWidget,
    );
    final done = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Done'),
    );
    expect(done.onPressed, isNull);
  });

  testWidgets('renders replies as metadata above the message body', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Reply',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$reply',
          sender: 'Alice',
          body: 'My actual reply',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
          reply: const ReplyPreview(sender: 'Bob', body: 'Original message'),
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    expect(find.text('Original message'), findsOneWidget);
    expect(find.text('My actual reply'), findsOneWidget);
    expect(find.textContaining('> <'), findsNothing);

    await _revealMessageActions(tester, find.text('My actual reply'));
    await tester.tap(find.byTooltip('Reply'));
    await tester.pump();
    expect(find.text('Replying to Alice'), findsOneWidget);
    await _enterComposer(tester, 'A second reply');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(backend.lastReplyToMessageId, r'$reply');
  });

  testWidgets('edits, deletes, and reacts through message actions', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Original',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$own',
          sender: 'Deltie',
          body: 'Original',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
          own: true,
          canRedact: true,
          reactions: const [
            ReactionSummary(key: '👍', count: 2, reactedByMe: true),
          ],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    await tester.tap(find.text('👍 2'));
    expect(backend.toggledReactions, [(r'$own', '👍')]);

    final hoverOnly = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hoverOnly.addPointer();
    await hoverOnly.moveTo(tester.getCenter(find.text('Original').last));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.byTooltip('Reply'), findsNothing);
    await hoverOnly.removePointer();

    await _revealMessageActions(tester, find.text('Original').last);
    expect(find.byTooltip('Reply'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.byTooltip('Reply'), findsNothing);

    await _revealMessageActions(tester, find.text('Original').last);
    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(find.text('Add reaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🎉'));
    await tester.pumpAndSettle();
    expect(backend.toggledReactions, [(r'$own', '👍'), (r'$own', '🎉')]);

    await _revealMessageActions(tester, find.text('Original').last);
    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    // Moving from the row into the popup used to dismiss the owning overlay
    // before the selected callback could run.
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(find.text('Edit message'));
    await tester.pump();
    expect(find.text('Editing message'), findsOneWidget);
    await _enterComposer(tester, 'Changed');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(backend.lastEditMessageId, r'$own');

    await _revealMessageActions(tester, find.text('Original').last);
    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(find.text('Delete message'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(backend.redactedMessageIds, [r'$own']);
  });

  testWidgets('loads older history from the timeline control', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreHistory = true
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Older messages exist',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$message',
          sender: 'Alice',
          body: 'Newest message',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    await tester.tap(find.text('Load older messages'));

    expect(backend.historyRequests, 1);
  });

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
    final composer = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(composer.focusNode.hasFocus, isTrue);
    await _enterComposer(tester, 'hello from Deltiecord');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(backend.sentMessages, ['hello from Deltiecord']);
    expect(find.text('hello from Deltiecord'), findsNothing);
    expect(composer.focusNode.hasFocus, isTrue);
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
    await _enterComposer(tester, '@ali');

    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
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
    await _enterComposer(tester, '@gen');

    expect(find.text('Room'), findsOneWidget);
    await tester.tap(find.text('general').last);
    await tester.pump();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText(), '#general \n');
  });

  testWidgets('renders Matrix rich text and revealable spoilers', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello secret',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$rich',
          sender: 'Alice',
          body: 'Hello secret',
          formattedBody:
              '<strong>Hello</strong> <span data-mx-spoiler>secret</span>',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    final richMessage = find.byType(MatrixHtmlText);
    final spoiler = find.descendant(
      of: richMessage,
      matching: find.textContaining('SPOILER'),
    );
    expect(spoiler, findsOneWidget);
    expect(
      find.descendant(of: richMessage, matching: find.textContaining('secret')),
      findsNothing,
    );
    await tester.tap(spoiler);
    await tester.pump();
    expect(
      find.descendant(
        of: richMessage,
        matching: find.textContaining('Hello secret'),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _enterComposer(WidgetTester tester, String text) async {
  final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
  editor.controller.document = Document()..insert(0, text);
  editor.controller.updateSelection(
    TextSelection.collapsed(offset: text.length),
    ChangeSource.local,
  );
  await tester.pump();
}

Future<void> _revealMessageActions(WidgetTester tester, Finder message) async {
  final mouse = await tester.createGesture(
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await mouse.addPointer();
  final position = tester.getCenter(message);
  await mouse.moveTo(position);
  await mouse.down(position);
  await mouse.up();
  await tester.pump();
  await mouse.moveTo(Offset.zero);
  await tester.pump();
  await mouse.removePointer();
}

class FakeBackend extends ChatBackend {
  SessionStatus currentStatus = SessionStatus.starting;
  List<RoomSummary> roomList = const [];
  RoomSummary? currentRoom;
  List<SpaceSummary> spaceList = const [];
  String? currentSpaceId;
  List<ChatMessage> messageList = const [];
  List<MentionSuggestion> mentionList = const [];
  bool moreHistory = false;
  int historyRequests = 0;
  final List<String> sentMessages = [];
  final List<String> redactedMessageIds = [];
  final List<(String, String)> toggledReactions = [];
  String? lastReplyToMessageId;
  String? lastEditMessageId;
  EncryptionSetupState security = const EncryptionSetupState(
    status: EncryptionSetupStatus.ready,
    keyBackupEnabled: true,
    crossSigningEnabled: true,
    deviceVerified: true,
  );

  @override
  String? get error => null;
  @override
  EncryptionSetupState get encryptionSetup => security;
  @override
  List<ChatMessage> get messages => messageList;
  @override
  List<MentionSuggestion> get mentionSuggestions => mentionList;
  @override
  List<String> get typingUserNames => const [];
  @override
  List<RoomMemberSummary> get selectedRoomMembers => const [];
  @override
  List<ChatMessage> get pinnedMessages => const [];
  @override
  List<RoomSummary> get rooms => roomList;
  @override
  List<SpaceSummary> get spaces => spaceList;
  @override
  String? get selectedSpaceId => currentSpaceId;
  @override
  RoomSummary? get selectedRoom => currentRoom;
  @override
  bool get selectedRoomMuted => false;
  @override
  bool get notificationPreviewsEnabled => true;
  @override
  SessionStatus get status => currentStatus;
  @override
  bool get timelineLoading => false;
  @override
  bool get historyLoading => false;
  @override
  bool get canLoadMoreHistory => moreHistory;
  @override
  String? get firstUnreadMessageId => null;
  @override
  VoiceConnectionStatus get voiceConnectionStatus =>
      VoiceConnectionStatus.disconnected;
  @override
  String? get activeVoiceRoomId => null;
  @override
  bool get voiceMuted => false;
  @override
  String? get voiceError => null;
  @override
  List<AudioInputSummary> get audioInputs => const [];
  @override
  String? get selectedAudioInputId => null;
  @override
  String? get userId => '@deltie:example.org';

  @override
  Future<void> initialize() async {}
  @override
  void clearError() {}
  @override
  Future<String> createEncryptionSetup() async => 'recovery-key';
  @override
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase) async {}
  @override
  Future<void> refreshEncryptionSetup() async {}
  @override
  void selectSpace(String? spaceId) {
    currentSpaceId = spaceId;
    currentRoom = null;
    notifyListeners();
  }

  @override
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<void> selectRoom(String roomId) async {
    currentRoom = roomList.firstWhere((room) => room.id == roomId);
    notifyListeners();
  }

  @override
  Future<void> setSelectedRoomMuted(bool muted) async {}
  @override
  Future<void> setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  ) async {}
  @override
  Future<void> setNotificationPreviewsEnabled(bool enabled) async {}
  @override
  Future<void> refreshAudioInputs() async {}
  @override
  Future<void> selectAudioInput(String? deviceId) async {}
  @override
  Future<void> joinVoiceRoom(String roomId) async {}
  @override
  Future<void> leaveVoiceRoom() async {}
  @override
  Future<void> setVoiceMuted(bool muted) async {}
  @override
  Future<void> setComposerTyping(bool typing) async {}
  @override
  List<ChatMessage> searchMessages(String query) => const [];

  @override
  Future<void> loadMoreHistory() async {
    historyRequests++;
  }

  @override
  Future<void> sendMessage(
    String text, {
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) async {
    sentMessages.add(text);
    lastReplyToMessageId = replyToMessageId;
    lastEditMessageId = editMessageId;
  }

  @override
  Future<void> redactMessage(String messageId) async {
    redactedMessageIds.add(messageId);
  }

  @override
  Future<void> retryMessage(String messageId) async {}
  @override
  Future<void> cancelPendingMessage(String messageId) async {}

  @override
  Future<void> toggleReaction(String messageId, String key) async {
    toggledReactions.add((messageId, key));
  }

  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? replyToMessageId,
  }) async {}

  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async => Uint8List(0);

  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) async =>
      null;
}
