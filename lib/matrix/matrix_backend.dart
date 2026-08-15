import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/chat_notifications.dart';
import 'matrix_client_factory.dart';
import 'media_range_proxy.dart';
import 'matrix_voice_controller.dart';

part 'matrix_event_mapping.dart';
part 'matrix_timeline_support.dart';
part 'matrix_room_metadata.dart';
part 'matrix_link_previews.dart';
part 'matrix_session.dart';
part 'matrix_crypto.dart';
part 'matrix_room_operations.dart';
part 'matrix_messages.dart';
part 'matrix_media.dart';

final _webUrlPattern = RegExp(r'https?://[^\s<>]+');

/// Matrix integration built on matrix-dart-sdk. Element and FluffyChat were
/// consulted as behavioral references; no source from either client is copied.
/// See CREDITS.md for project links and license information.
class MatrixBackend extends ChatBackend {
  static const _settingsAccountDataType = 'net.deltiecord.settings';
  static const _roomPresentationEventType = deltiecordRoomPresentationEventType;

  MatrixBackend({ChatNotificationSink? notifications})
    : _notifications = notifications ?? const SilentChatNotificationSink();

  final ChatNotificationSink _notifications;
  Client? _client;
  Timeline? _timeline;
  MatrixVoiceController? _voice;
  Timer? _typingStopTimer;
  String? _typingRoomId;
  StreamSubscription<Object?>? _syncSubscription;
  StreamSubscription<Object?>? _loginSubscription;
  StreamSubscription<Object?>? _syncStatusSubscription;
  SessionStatus _status = SessionStatus.starting;
  ConnectionStatus _connectionStatus = ConnectionStatus.connecting;
  String? _error;
  String? _selectedRoomId;
  String? _selectedSpaceId;
  int _timelineGeneration = 0;
  bool _timelineLoading = false;
  bool _historyLoading = false;
  final Set<String> _loadedBackupRoomIds = {};
  final Map<String, Uint8List> _avatarBytes = {};
  final Map<String, Uri?> _avatarUris = {};
  final Map<String, Uint8List> _senderAvatarBytes = {};
  final Map<String, Uri?> _senderAvatarUris = {};
  final Map<String, String> _decryptedPreviews = {};
  final Map<String, ReplyPreview> _replyPreviews = {};
  final Map<String, LinkPreview?> _linkPreviews = {};
  final HttpClient _previewHttpClient = HttpClient()
    ..userAgent = 'Deltiecord/0.3 link preview';
  final Set<String> _outboundSessionsReset = {};
  bool _refreshingRoomMetadata = false;
  bool _roomMetadataRefreshRequested = false;
  final Set<String> _roomsMarkingRead = {};
  final Map<String, String> _lastMarkedReadEventIds = {};
  final Map<String, String?> _firstUnreadEventIds = {};
  final Map<String, String> _lastNotificationEventIds = {};
  final Map<String, RoomPresentation> _roomPresentationOverrides = {};
  bool _notificationsPrimed = false;
  bool _notificationPreviewsEnabled = true;
  AppPreferences _preferences = const AppPreferences();
  int? _maximumUploadBytes;
  List<DeviceSessionSummary> _deviceSessions = const [];
  bool _devicesLoading = false;
  final MediaRangeProxy _mediaRangeProxy = MediaRangeProxy();
  final Map<String, MediaPlaybackSource> _mediaPlaybackSources = {};
  EncryptionSetupState _encryptionSetup = const EncryptionSetupState(
    status: EncryptionSetupStatus.loading,
  );

  Client get _matrix => _client!;

  @override
  SessionStatus get status => _status;
  @override
  ConnectionStatus get connectionStatus => _connectionStatus;
  @override
  String? get error => _error;
  @override
  String? get userId => _client?.userID;
  @override
  String? get deviceId => _client?.deviceID;
  @override
  Uri? get homeserver => _client?.homeserver;
  @override
  AppPreferences get preferences => _preferences;
  @override
  EncryptionSetupState get encryptionSetup => _encryptionSetup;
  @override
  String? get selectedSpaceId => _selectedSpaceId;
  @override
  List<SpaceSummary> get spaces => _joinedRooms
      .where((room) => room.isSpace)
      .map(
        (room) => SpaceSummary(
          id: room.id,
          name: room.getLocalizedDisplayname(),
          avatarBytes: _avatarBytes[room.id],
        ),
      )
      .toList(growable: false);
  @override
  bool get timelineLoading => _timelineLoading;
  @override
  bool get historyLoading => _historyLoading;
  @override
  bool get canLoadMoreHistory => _timeline?.canRequestHistory ?? false;
  @override
  String? get firstUnreadMessageId => _firstUnreadEventIds[_selectedRoomId];
  @override
  VoiceConnectionStatus get voiceConnectionStatus =>
      _voice?.status ?? VoiceConnectionStatus.disconnected;
  @override
  String? get activeVoiceRoomId => _voice?.activeRoomId;
  @override
  bool get voiceMuted => _voice?.muted ?? false;
  @override
  String? get voiceError => _voice?.error;
  @override
  List<AudioInputSummary> get audioInputs => _voice?.audioInputs ?? const [];
  @override
  String? get selectedAudioInputId => _voice?.selectedAudioInputId;
  @override
  List<DeviceSessionSummary> get deviceSessions => _deviceSessions;
  @override
  bool get devicesLoading => _devicesLoading;
  @override
  List<MentionSuggestion> get mentionSuggestions {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    final suggestions = room
        .getParticipants()
        .map(
          (user) => MentionSuggestion(
            matrixId: user.id,
            displayName: user.calcDisplayname(),
          ),
        )
        .toList();
    suggestions.addAll(
      _joinedRooms
          .where((room) => !room.isSpace)
          .map(
            (room) => MentionSuggestion(
              matrixId: room.id,
              displayName: room.getLocalizedDisplayname(),
              isRoom: true,
            ),
          ),
    );
    suggestions.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return suggestions;
  }

  @override
  List<String> get typingUserNames {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    return room.typingUsers
        .where((user) => user.id != _matrix.userID)
        .map((user) => user.calcDisplayname())
        .toList(growable: false);
  }

  @override
  List<RoomMemberSummary> get selectedRoomMembers {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    final members = room
        .getParticipants()
        .map((user) {
          // The SDK's synchronous cache is required while building this getter;
          // network refreshes arrive through sync and notify the UI separately.
          // ignore: deprecated_member_use
          final presence = _matrix.presences[user.id]?.presence;
          return RoomMemberSummary(
            userId: user.id,
            displayName: user.calcDisplayname(),
            avatarBytes:
                _senderAvatarBytes['${room.id}|${user.id}'] ??
                _senderAvatarBytes[user.id],
            presence: switch (presence) {
              PresenceType.online => UserPresence.online,
              PresenceType.unavailable => UserPresence.away,
              _ => UserPresence.offline,
            },
          );
        })
        .toList(growable: false);
    members.sort((a, b) {
      final presenceOrder = a.presence.index.compareTo(b.presence.index);
      return presenceOrder != 0
          ? presenceOrder
          : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return members;
  }

  @override
  List<ChatMessage> get pinnedMessages {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    final pinned = room.pinnedEventIds.toSet();
    return messages.where((message) => pinned.contains(message.id)).toList();
  }

  @override
  List<ChatMessage> searchMessages(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return messages
        .where(
          (message) =>
              message.body.toLowerCase().contains(normalized) ||
              message.sender.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  @override
  bool get notificationPreviewsEnabled => _notificationPreviewsEnabled;

  @override
  List<RoomSummary> get rooms {
    final selectedSpaceId = _selectedSpaceId;
    final visible = selectedSpaceId == null
        ? _homeRooms
        : _roomsForSpace(selectedSpaceId);
    return visible.map(_roomSummary).toList(growable: false);
  }

  List<Room> get _joinedRooms =>
      _client?.rooms
          .where((room) => room.membership == Membership.join)
          .toList(growable: false) ??
      const [];

  Set<String> get _allSpaceChildIds => _joinedRooms
      .where((room) => room.isSpace)
      .expand((space) => space.spaceChildren)
      .map((child) => child.roomId)
      .whereType<String>()
      .toSet();

  List<Room> get _homeRooms => _joinedRooms
      .where(
        (room) =>
            !room.isSpace &&
            (room.isDirectChat || !_allSpaceChildIds.contains(room.id)),
      )
      .toList(growable: false);

  @override
  RoomSummary? get selectedRoom => _selectedRoomSummary;

  @override
  bool get selectedRoomMuted => _selectedRoomIsMuted;

  @override
  List<ChatMessage> get messages => _mappedMessages;

  void _notifyBackendListeners() => notifyListeners();

  @override
  Future<void> initialize() => _initializeSession();

  @override
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  }) => _loginSession(
    homeserver: homeserver,
    username: username,
    password: password,
  );

  @override
  Future<void> logout() => _logoutSession();

  @override
  Future<void> refreshAudioInputs() => _refreshAudioInputs();

  @override
  Future<void> selectAudioInput(String? deviceId) =>
      _selectAudioInput(deviceId);

  @override
  Future<void> refreshDevices() => _refreshDevices();

  @override
  Future<void> joinVoiceRoom(String roomId) => _joinVoiceRoom(roomId);

  @override
  Future<void> setVoiceMuted(bool muted) => _setVoiceMuted(muted);

  @override
  Future<void> leaveVoiceRoom() => _leaveVoiceRoom();

  @override
  Future<void> setComposerTyping(bool typing) => _setComposerTyping(typing);

  @override
  Future<void> setNotificationPreviewsEnabled(bool enabled) =>
      _setNotificationPreviewsEnabled(enabled);

  @override
  Future<void> updatePreferences(AppPreferences preferences) =>
      _updatePreferences(preferences);

  @override
  void clearError() => _clearSessionError();
  @override
  Future<void> refreshEncryptionSetup() => _refreshEncryptionSetup();

  @override
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase) =>
      _recoverEncryption(recoveryKeyOrPassphrase);

  @override
  Future<String> createEncryptionSetup() => _createEncryptionSetup();
  @override
  void selectSpace(String? spaceId) => _selectSpace(spaceId);

  @override
  Future<void> selectRoom(String roomId) => _selectRoom(roomId);

  @override
  Future<void> setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  ) => _setRoomPresentation(roomId, presentation);

  @override
  Future<void> createRoom({
    required String name,
    required RoomPresentation presentation,
  }) => _createRoom(name: name, presentation: presentation);

  @override
  Future<void> renameRoom(String roomId, String name) =>
      _renameRoom(roomId, name);

  @override
  Future<void> setSelectedRoomMuted(bool muted) => _setSelectedRoomMuted(muted);
  @override
  Future<void> loadMoreHistory() => _loadMoreHistory();

  @override
  Future<void> sendMessage(
    String body, {
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) => _sendMessage(
    body,
    formattedBody: formattedBody,
    replyToMessageId: replyToMessageId,
    editMessageId: editMessageId,
  );

  @override
  Future<void> redactMessage(String messageId) => _redactMessage(messageId);

  @override
  Future<void> retryMessage(String messageId) => _retryMessage(messageId);

  @override
  Future<void> cancelPendingMessage(String messageId) =>
      _cancelPendingMessage(messageId);

  @override
  Future<void> toggleReaction(String messageId, String key) =>
      _toggleReaction(messageId, key);
  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? replyToMessageId,
  }) => _sendAttachment(attachment, replyToMessageId: replyToMessageId);

  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) => _downloadAttachment(messageId, thumbnail: thumbnail);

  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) =>
      _getMediaPlaybackSource(messageId);

  Future<void> _closeTimeline() async {
    _timelineGeneration++;
    _timeline?.cancelSubscriptions();
    _timeline = null;
  }

  String _friendlyError(Object exception) {
    final message = exception.toString().replaceFirst('Exception: ', '');
    return message.length > 240 ? '${message.substring(0, 240)}…' : message;
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    final voice = _voice;
    _voice = null;
    voice?.removeListener(notifyListeners);
    voice?.dispose();
    _timeline?.cancelSubscriptions();
    _syncSubscription?.cancel();
    _loginSubscription?.cancel();
    _syncStatusSubscription?.cancel();
    _client?.dispose();
    unawaited(_mediaRangeProxy.close());
    _previewHttpClient.close(force: true);
    super.dispose();
  }
}
