import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';

/// Matrix-independent application boundary consumed by Flutter widgets.
///
/// Keeping SDK objects behind this contract lets desktop and future Android
/// interfaces share the same session, room, timeline, and crypto behavior.
abstract class ChatBackend extends ChangeNotifier {
  SessionStatus get status;
  String? get error;
  String? get userId;
  EncryptionSetupState get encryptionSetup;
  List<SpaceSummary> get spaces;
  String? get selectedSpaceId;
  List<RoomSummary> get rooms;
  RoomSummary? get selectedRoom;
  bool get selectedRoomMuted;
  List<ChatMessage> get messages;
  List<MentionSuggestion> get mentionSuggestions;
  bool get timelineLoading;
  bool get historyLoading;
  bool get canLoadMoreHistory;
  String? get firstUnreadMessageId;

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
  Future<void> setSelectedRoomMuted(bool muted);
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
