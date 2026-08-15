import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';

/// Matrix-independent application boundary consumed by Flutter widgets.
///
/// Keeping SDK objects behind this contract lets desktop and future Android
/// interfaces share the same session, room, timeline, and crypto behavior.
abstract class ChatBackend extends ChangeNotifier {
  SessionStatus get status;
  ConnectionStatus get connectionStatus;
  String? get error;
  String? get userId;
  String? get deviceId;
  Uri? get homeserver;
  AppPreferences get preferences;
  EncryptionSetupState get encryptionSetup;
  List<SpaceSummary> get spaces;
  String? get selectedSpaceId;
  List<RoomSummary> get rooms;
  RoomSummary? get selectedRoom;
  bool get selectedRoomMuted;
  bool get notificationPreviewsEnabled;
  List<ChatMessage> get messages;
  List<MentionSuggestion> get mentionSuggestions;
  List<String> get typingUserNames;
  List<RoomMemberSummary> get selectedRoomMembers;
  List<ChatMessage> get pinnedMessages;
  bool get timelineLoading;
  bool get historyLoading;
  bool get canLoadMoreHistory;
  String? get firstUnreadMessageId;
  VoiceConnectionStatus get voiceConnectionStatus;
  String? get activeVoiceRoomId;
  bool get voiceMuted;
  String? get voiceError;
  List<AudioInputSummary> get audioInputs;
  String? get selectedAudioInputId;

  Future<void> initialize();
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  });
  Future<void> logout();
  void clearError();
  Future<void> refreshEncryptionSetup();
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase);
  Future<String> createEncryptionSetup();
  void selectSpace(String? spaceId);
  Future<void> selectRoom(String roomId);
  Future<void> setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  );
  Future<void> createRoom({
    required String name,
    required RoomPresentation presentation,
  });
  Future<void> renameRoom(String roomId, String name);
  Future<void> refreshAudioInputs();
  Future<void> selectAudioInput(String? deviceId);
  Future<void> joinVoiceRoom(String roomId);
  Future<void> leaveVoiceRoom();
  Future<void> setVoiceMuted(bool muted);
  Future<void> setComposerTyping(bool typing);
  List<ChatMessage> searchMessages(String query);
  Future<void> setSelectedRoomMuted(bool muted);
  Future<void> setNotificationPreviewsEnabled(bool enabled);
  Future<void> updatePreferences(AppPreferences preferences);
  Future<void> loadMoreHistory();
  Future<void> sendMessage(
    String text, {
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  });
  Future<void> redactMessage(String messageId);
  Future<void> retryMessage(String messageId);
  Future<void> cancelPendingMessage(String messageId);
  Future<void> toggleReaction(String messageId, String key);
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? replyToMessageId,
  });
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  });
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId);
}
