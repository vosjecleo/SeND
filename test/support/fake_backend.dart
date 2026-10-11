import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:deltiecord/backend/chat_backend.dart';
import 'package:deltiecord/models/chat_models.dart';

class FakeBackend extends ChatBackend {
  final sentInvites = <(String, String?)>[];
  @override
  bool canInviteToRoom(String roomId) => editableRoomIds.contains(roomId);
  @override
  Future<void> inviteMember(
    String userId, {
    String? reason,
    String? roomId,
  }) async {
    sentInvites.add((userId, roomId));
  }

  final editableRoomIds = <String>{};
  @override
  bool canChangeRoomState(String roomId, String eventType) =>
      editableRoomIds.contains(roomId);
  @override
  List<ChannelCategorySummary> get selectedSpaceCategories => categoryList;
  bool failCategoryCreation = false;

  @override
  Future<void> createChannelCategory(String name) async {
    if (failCategoryCreation) throw StateError('Save failed');
    categoryList = [
      ...categoryList,
      ChannelCategorySummary(id: name, name: name, roomIds: const []),
    ];
    notifyListeners();
  }

  @override
  Future<void> renameChannelCategory(String categoryId, String name) async {}

  @override
  Future<void> deleteChannelCategory(String categoryId) async {}

  @override
  Future<void> reorderChannelCategory(String categoryId, int newIndex) async {}

  @override
  Future<void> setChannelCategoryCollapsed(
    String categoryId,
    bool collapsed,
  ) async => categoryCollapseChanges.add((categoryId, collapsed));

  @override
  bool canManageSpaceChannelLayout(String spaceId) => mayArrangeChannels;

  @override
  Future<void> moveRoomInSpace(
    String roomId, {
    String? categoryId,
    String? beforeRoomId,
  }) async => roomMoves.add((roomId, categoryId, beforeRoomId));

  SessionStatus currentStatus = SessionStatus.starting;
  ConnectionStatus currentConnectionStatus = ConnectionStatus.online;
  List<RoomSummary> roomList = const [];
  RoomSummary? currentRoom;
  List<SpaceSummary> spaceList = const [];
  List<ChannelCategorySummary> categoryList = const [];
  String? currentSpaceId;
  List<ChatMessage> messageList = const [];
  List<DeviceSessionSummary> deviceList = const [];
  List<MentionSuggestion> mentionList = const [];
  List<RoomMemberSummary> memberList = const [];
  List<String> typingNames = const [];
  List<StickerPackSummary> stickerPackList = const [];
  AppPreferences currentPreferences = const AppPreferences();
  bool moreHistory = false;
  bool moreFuture = false;
  VoiceConnectionStatus currentVoiceStatus = VoiceConnectionStatus.disconnected;
  String? currentActiveVoiceId;
  bool deafened = false;
  bool muted = false;
  bool cameraEnabled = false;
  bool mayArrangeChannels = true;
  Completer<void>? sendGate;
  int historyRequests = 0;
  int futureRequests = 0;
  String? lastHistoryAnchor;
  String? lastFutureAnchor;
  int jumpPresentRequests = 0;
  int profileRefreshRequests = 0;
  int applicationRefreshCount = 0;
  Future<void> Function()? historyLoader;
  final List<String> sentMessages = [];
  final List<String?> sentFormattedBodies = [];
  final List<String?> sentMessageRoomIds = [];
  final List<String?> sentAttachmentRoomIds = [];
  final List<String> redactedMessageIds = [];
  final List<String> cancelledMessageIds = [];
  final List<String> retriedMessageIds = [];
  final List<(String, String)> toggledReactions = [];
  final List<(String, bool)> mutedRooms = [];
  final List<(String, bool)> categoryCollapseChanges = [];
  final List<(String, String?, String?)> roomMoves = [];
  final List<String> jumpedEventIds = [];
  final List<bool> applicationForegroundStates = [];
  final List<bool> conversationVisibilityStates = [];
  final List<bool> conversationAtPresentStates = [];
  String? lastReplyToMessageId;
  String? lastEditMessageId;
  String? removedDeviceId;
  String? removalPassword;
  String? startedDirectMessageWith;
  String? leftRoomId;
  UserProfileSummary? testProfile;
  int testProfileRevision = 0;
  Completer<UserProfileSummary>? profileCompleter;
  EncryptionSetupState security = const EncryptionSetupState(
    status: EncryptionSetupStatus.ready,
    keyBackupEnabled: true,
    crossSigningEnabled: true,
    deviceVerified: true,
  );

  @override
  void setApplicationForeground(bool foreground) =>
      applicationForegroundStates.add(foreground);

  @override
  void refreshApplicationState() => applicationRefreshCount++;

  @override
  void setConversationVisible(bool visible) =>
      conversationVisibilityStates.add(visible);

  @override
  void setConversationAtPresent(bool atPresent) =>
      conversationAtPresentStates.add(atPresent);

  @override
  String? get error => null;
  @override
  String? get deviceId => 'TESTDEVICE';
  @override
  Uri? get homeserver => Uri.parse('https://matrix.example.org');
  @override
  String? get profileDisplayName => 'Deltie';
  @override
  Uint8List? get profileAvatarBytes => null;
  @override
  UserPresence get profilePresence => UserPresence.online;
  @override
  String? get profileStatusMessage => testProfile?.statusMessage;
  @override
  int? get profileColor => testProfile?.profileColor;
  @override
  bool get profileLoading => false;
  @override
  int get profileRevision => testProfileRevision;
  @override
  AppPreferences get preferences => currentPreferences;
  @override
  EncryptionSetupState get encryptionSetup => security;
  @override
  List<ChatMessage> get messages => messageList;
  @override
  List<MentionSuggestion> get mentionSuggestions => mentionList;
  @override
  List<String> get typingUserNames => typingNames;
  @override
  List<StickerPackSummary> get stickerPacks => stickerPackList;

  void setTypingNames(List<String> names) {
    typingNames = names;
    notifyListeners();
  }

  @override
  List<RoomMemberSummary> get selectedRoomMembers => memberList;
  @override
  int get storageUsageBytes => 0;
  @override
  bool get storageLoading => false;
  @override
  List<String> get blockedUserIds => const [];
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
  ConnectionStatus get connectionStatus => currentConnectionStatus;
  @override
  bool get timelineLoading => false;
  @override
  bool get historyLoading => false;
  @override
  bool get canLoadMoreHistory => moreHistory;
  @override
  bool get canLoadMoreFuture => moreFuture;
  @override
  bool get atTimelinePresent => !moreFuture;
  @override
  String? get firstUnreadMessageId => null;
  @override
  VoiceConnectionStatus get voiceConnectionStatus => currentVoiceStatus;
  @override
  String? get activeVoiceRoomId => currentActiveVoiceId;
  @override
  bool get voiceMuted => muted;
  @override
  bool get voiceDeafened => deafened;
  @override
  bool get voiceCameraEnabled => cameraEnabled;
  @override
  bool get voiceScreenSharing => false;
  @override
  double get voiceInputLevel => 0;
  @override
  String? get voiceError => null;
  @override
  List<AudioInputSummary> get audioInputs => const [];
  @override
  String? get selectedAudioInputId => null;
  @override
  List<RtcDeviceSummary> get audioOutputs => const [];
  @override
  String? get selectedAudioOutputId => null;
  @override
  List<RtcDeviceSummary> get cameras => const [];
  @override
  String? get selectedCameraId => null;
  @override
  List<RtcMediaStreamSummary> get rtcMediaStreams => const [];
  @override
  List<DeviceSessionSummary> get deviceSessions => deviceList;
  @override
  bool get devicesLoading => false;
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
  Future<void> setRoomMuted(String roomId, bool muted) async {
    mutedRooms.add((roomId, muted));
  }

  @override
  Future<void> setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  ) async {}
  @override
  Future<void> createRoom({
    required String name,
    required RoomPresentation presentation,
    String topic = '',
    bool encrypted = true,
  }) async {}
  @override
  Future<void> createSpace({
    required String name,
    String topic = '',
    bool encrypted = true,
  }) async {}
  @override
  Future<void> renameRoom(String roomId, String name) async {}
  @override
  Future<void> setRoomTopic(String roomId, String topic) async {}
  @override
  Future<void> setRoomAvatar(String roomId, Uint8List? bytes) async {}
  @override
  Future<void> leaveRoom(String roomId) async {
    leftRoomId = roomId;
    roomList = roomList.where((room) => room.id != roomId).toList();
    if (currentRoom?.id == roomId) currentRoom = null;
    notifyListeners();
  }

  @override
  Future<void> setMemberPowerLevel(String userId, int powerLevel) async {}
  @override
  Future<UserProfileSummary> getUserProfile(
    String userId, {
    bool refresh = false,
  }) async {
    if (refresh) profileRefreshRequests++;
    return profileCompleter?.future ??
        testProfile ??
        UserProfileSummary(userId: userId, displayName: userId);
  }

  @override
  Future<void> updateOwnProfileFields({
    String? bio,
    String? pronouns,
    String? timezone,
    String? statusMessage,
    int? profileColor,
    int? profileColorSecondary,
    Uint8List? bannerBytes,
    bool removeBanner = false,
  }) async {}
  @override
  Future<void> startDirectChat(String userId) async {
    startedDirectMessageWith = userId;
  }

  @override
  Future<List<SpaceDirectoryEntry>> searchPublicSpaces(String query) async =>
      const [];
  @override
  Future<void> joinPublicSpace(String roomId) async {}
  @override
  Future<void> setUserBlocked(String userId, bool blocked) async {}
  @override
  Future<void> refreshStorageUsage() async {}
  @override
  Future<void> clearMediaCache() async {}
  @override
  Future<void> jumpToPresent() async {
    jumpPresentRequests++;
  }

  @override
  Future<void> loadMoreFuture({String? anchorEventId}) async {
    futureRequests++;
    lastFutureAnchor = anchorEventId;
  }

  @override
  Future<List<ChatMessage>> loadPinnedMessages() async => pinnedMessages;
  @override
  Future<void> jumpToEvent(String eventId) async {
    jumpedEventIds.add(eventId);
  }

  @override
  Future<void> setNotificationPreviewsEnabled(bool enabled) async {}
  @override
  Future<void> updatePreferences(AppPreferences preferences) async {
    currentPreferences = preferences;
    notifyListeners();
  }

  @override
  Future<void> refreshAudioInputs() async {}
  @override
  Future<void> selectAudioInput(String? deviceId) async {}
  @override
  Future<void> selectAudioOutput(String? deviceId) async {}
  @override
  Future<void> selectCamera(String? deviceId) async {}
  @override
  Future<void> refreshDevices() async {}
  @override
  Future<void> refreshProfile() async {}
  @override
  Future<void> setProfileDisplayName(String displayName) async {}
  @override
  Future<void> setProfileAvatar(
    Uint8List? bytes, {
    String fileName = 'avatar.png',
    String mimeType = 'image/png',
  }) async {}
  @override
  Future<void> removeDevice(String deviceId, String password) async {
    removedDeviceId = deviceId;
    removalPassword = password;
  }

  @override
  Future<void> deleteAccount(String password) async {}
  @override
  Future<void> joinVoiceRoom(String roomId) async {}
  @override
  Future<void> leaveVoiceRoom() async {}
  @override
  Future<void> setVoiceMuted(bool value) async {
    muted = value;
    notifyListeners();
  }

  @override
  Future<void> setVoiceDeafened(bool value) async {
    deafened = value;
    notifyListeners();
  }

  @override
  Future<void> setVoiceCameraEnabled(bool enabled) async {}
  @override
  Future<void> setVoiceScreenSharing(bool enabled) async {}
  @override
  Future<void> setParticipantVolume(String userId, double volume) async {}
  @override
  Future<void> setParticipantLocallyMuted(String userId, bool muted) async {}
  @override
  Future<void> setComposerTyping(bool typing) async {}
  @override
  List<ChatMessage> searchMessages(String query) => const [];
  @override
  Future<List<ChatMessage>> searchRoomHistory(String query) async =>
      searchMessages(query);

  @override
  Future<void> loadMoreHistory({String? anchorEventId}) async {
    historyRequests++;
    lastHistoryAnchor = anchorEventId;
    await historyLoader?.call();
  }

  @override
  Future<void> sendMessage(
    String text, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) async {
    sentMessages.add(text);
    sentFormattedBodies.add(formattedBody);
    sentMessageRoomIds.add(roomId);
    lastReplyToMessageId = replyToMessageId;
    lastEditMessageId = editMessageId;
    await sendGate?.future;
  }

  @override
  Future<void> redactMessage(String messageId) async {
    redactedMessageIds.add(messageId);
  }

  @override
  Future<void> retryMessage(String messageId) async {
    retriedMessageIds.add(messageId);
  }

  @override
  Future<void> cancelPendingMessage(String messageId) async {
    cancelledMessageIds.add(messageId);
  }

  @override
  Future<void> toggleReaction(
    String messageId,
    String key, {
    CustomEmojiReference? customEmoji,
  }) async {
    toggledReactions.add((messageId, key));
  }

  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) async {
    sentAttachmentRoomIds.add(roomId);
  }

  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async => Uint8List(0);

  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) async =>
      null;
  @override
  Future<String?> getAttachmentReference(String messageId) async => null;
}
