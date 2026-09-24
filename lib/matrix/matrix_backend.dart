import 'dart:async';
import '../services/settings_echo_guard.dart';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import '../services/platform_io.dart';
import '../services/browser_media.dart';
import '../services/browser_push.dart';
import '../services/gif_service.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';
import '../backend/chat_backend.dart';
import '../backend/thread_session.dart';
import '../models/forum_post.dart';
import '../models/login_methods.dart';
import '../services/auth_browser.dart';
import '../services/auth_callback.dart';
import '../models/chat_models.dart';
import '../models/room_event_visibility.dart';
import '../services/receipt_positions.dart';
import '../models/space_administration.dart';
import '../services/chat_notifications.dart';
import '../services/favourite_reactions_store.dart';
import '../services/custom_emoji.dart';
import '../services/avatar_media_pool.dart';
import '../services/coalesced_callback.dart';
import '../services/device_appearance_store.dart';
import '../services/account_settings_sync.dart';
import '../services/app_sounds.dart';
import '../services/android_push_bridge.dart';
import '../services/font_preferences.dart';
import '../services/message_search.dart';
import '../services/link_preview_policy.dart';
import '../services/link_preview_service.dart';
import '../services/web_preview_proxy.dart';
import '../services/message_order.dart';
import '../services/profile_refresh_policy.dart';
import '../services/profile_text.dart';
import '../services/poll_tally.dart';
import '../services/personal_sticker_packs.dart';
import '../services/secret_redaction.dart';
import '../services/scheduled_message_store.dart';
import '../services/timeline_window_policy.dart';
import '../services/unified_push.dart';
import 'matrix_client_factory.dart';
import 'media_range_proxy.dart';
import 'matrix_push_reconciliation.dart';
import 'matrix_voice_controller.dart';

part 'matrix_event_mapping.dart';
part 'matrix_timeline_support.dart';
part 'matrix_room_metadata.dart';
part 'matrix_link_previews.dart';
part 'matrix_session.dart';
part 'matrix_browser_auth.dart';
part 'matrix_crypto.dart';
part 'matrix_room_operations.dart';
part 'matrix_administration.dart';
part 'matrix_messages.dart';
part 'matrix_threads.dart';
part 'matrix_media.dart';
part 'matrix_profiles.dart';
part 'matrix_advanced_features.dart';

bool get _isMobilePlatform =>
    Platform.isAndroid ||
    Platform.isIOS ||
    (kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS));

double get _platformDefaultFontScale => _isMobilePlatform ? 1.1 : 1;

String get _platformFontScaleKey =>
    _isMobilePlatform ? 'mobile_font_scale' : 'desktop_font_scale';

double _readPlatformFontScale(Map<String, dynamic>? content) {
  final platformValue = (content?[_platformFontScaleKey] as num?)?.toDouble();
  if (platformValue != null) return platformValue.clamp(0.8, 1.4);
  final legacyValue = (content?['font_scale'] as num?)?.toDouble();
  // Older releases wrote one cross-platform value. Treat their untouched 100%
  // mobile value as the old default, while preserving deliberate custom sizes.
  if (_isMobilePlatform && legacyValue == 1) return 1.1;
  return legacyValue?.clamp(0.8, 1.4) ?? _platformDefaultFontScale;
}

/// Matrix integration built on matrix-dart-sdk. Element and FluffyChat were
/// consulted as behavioral references; no source from either client is copied.
/// See CREDITS.md for project links and license information.
class MatrixBackend extends ChatBackend {
  final Set<_MatrixThreadSession> _threadSessions = {};
  final Map<String, Event> _forumRoots = {};
  String? _forumCursor;
  bool _forumHasMore = true;
  bool _forumLoading = false;
  @override
  bool get canLoadMoreForumThreads => _forumHasMore;
  @override
  Future<void> loadForumThreads({bool refresh = false}) =>
      _loadForumThreads(refresh: refresh);
  ({String roomId, String rootId, int revision})? _threadNavigationRequest;
  @override
  ({String roomId, String rootId, int revision})? get threadNavigationRequest =>
      _threadNavigationRequest;
  bool _browserAuthenticationActive = false;
  bool _browserAuthenticationCanceled = false;
  AuthBrowser? _activeAuthBrowser;

  @override
  Future<void> cancelBrowserLogin() async {
    _browserAuthenticationCanceled = true;
    await _activeAuthBrowser?.close();
  }

  @override
  Future<LoginMethods> discoverLoginMethods(Uri homeserver) =>
      _discoverLoginMethods(homeserver);

  @override
  Future<void> loginWithBrowser(Uri homeserver, {required bool oidc}) =>
      _loginWithBrowser(homeserver, oidc: oidc);

  @override
  Future<void> createForumPost(
    String roomId,
    ForumPost post,
    String body, {
    AttachmentDraft? cover,
  }) async {
    final checked = ForumPost.validated(post.title, post.tags);
    final room = _matrix.getRoomById(roomId);
    if (room == null ||
        room.membership != Membership.join ||
        _presentationFor(room) != RoomPresentation.forum) {
      throw StateError('This forum is unavailable.');
    }
    if (body.trim().isEmpty) {
      throw const FormatException('Write a post before sending.');
    }
    await _prepareEncryptedSend(room);
    if (cover != null) {
      if (!cover.mimeType.startsWith('image/')) {
        throw const FormatException('Choose an image for the post cover.');
      }
      await _sendAttachment(
        AttachmentDraft(
          bytes: cover.bytes,
          name: cover.name,
          mimeType: cover.mimeType,
          spoiler: cover.spoiler,
          caption: '${checked.title}\n\n${body.trim()}',
        ),
        roomId: roomId,
        additionalContent: {forumPostKey: checked.toJson()},
      );
      return;
    }
    await room.sendEvent({
      'msgtype': MessageTypes.Text,
      'body': '${checked.title}\n\n${body.trim()}',
      forumPostKey: checked.toJson(),
    });
  }

  @override
  Future<ThreadSession> openThread(String roomId, String rootId) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      throw StateError('Join the room before opening its discussions.');
    }
    final session = _MatrixThreadSession(this, room, rootId);
    _threadSessions.add(session);
    try {
      await session.initialize();
      return session;
    } catch (_) {
      session.dispose();
      rethrow;
    }
  }

  static const _maximumCachedProfiles = 48;
  static const _maximumCachedProfileMediaBytes = 32 * 1024 * 1024;
  static const _maximumCachedAttachmentBytes = 64 * 1024 * 1024;
  static const _maximumCachedAttachments = 64;
  static const _settingsAccountDataType = 'net.deltiecord.settings';
  static const _deviceActivityAccountDataType =
      'net.deltiecord.device_activity';
  static const _activeCallDeviceAccountDataType =
      'net.deltiecord.active_call_device';
  static const _roomPresentationEventType = deltiecordRoomPresentationEventType;
  static const _spaceChannelsEventType = deltiecordSpaceChannelsEventType;
  static const _bookmarksAccountDataType = 'net.deltiecord.bookmarks';
  static const _spacePagesEventType = 'net.deltiecord.space.pages';
  static const _spaceProfileAccountDataType =
      'net.deltiecord.space_profile_overrides';
  static const _roomTimeoutsEventType = 'net.deltiecord.room.timeouts';

  MatrixBackend({
    ChatNotificationSink? notifications,
    DirectLinkPreviewFetcher? directPreviewFetcher,
    AvatarMediaPool? avatarMediaPool,
    DeviceAppearanceStore? deviceAppearanceStore,
  }) : _notifications = notifications ?? const SilentChatNotificationSink(),
       _directPreviewFetcher =
           directPreviewFetcher ?? DirectLinkPreviewFetcher(),
       _avatarMediaPool = avatarMediaPool ?? AvatarMediaPool(),
       _deviceAppearanceStore =
           deviceAppearanceStore ?? DeviceAppearanceStore();

  final ChatNotificationSink _notifications;
  final DirectLinkPreviewFetcher _directPreviewFetcher;
  final AvatarMediaPool _avatarMediaPool;
  final DeviceAppearanceStore _deviceAppearanceStore;
  Client? _client;
  Timeline? _timeline;
  MatrixVoiceController? _voice;
  Timer? _typingStopTimer;
  late final _backendUpdates = CoalescedCallback(
    notifyListeners,
    enabled: kIsWeb,
  );
  int _inboxRequestRevision = 0;
  @override
  int get inboxRequestRevision => _inboxRequestRevision;
  @override
  int get pendingInviteCount =>
      _client?.rooms
          .where((room) => room.membership == Membership.invite)
          .length ??
      0;
  Timer? _settingsSaveTimer;
  AppPreferences? _pendingPreferences;
  final _settingsEchoGuard = SettingsEchoGuard();
  Future<void> _preferencesWriteQueue = Future.value();
  String? _typingRoomId;
  StreamSubscription<Object?>? _syncSubscription;
  StreamSubscription<Object?>? _loginSubscription;
  StreamSubscription<Object?>? _syncStatusSubscription;
  StreamSubscription<NotificationTarget>? _notificationSubscription;
  StreamSubscription<String>? _unifiedPushSubscription;
  bool _unifiedPushRestoreRunning = false;
  DateTime? _lastUnifiedPushRestore;
  SessionStatus _status = SessionStatus.starting;
  ConnectionStatus _connectionStatus = ConnectionStatus.connecting;
  String? _error;
  String? _selectedRoomId;
  String? _selectedSpaceId;
  int _timelineGeneration = 0;
  bool _timelineLoading = false;
  bool _historyLoading = false;
  int _timelineDatabaseOffset = 0;
  bool _timelineDatabaseExhausted = false;
  bool _timelineServerExhausted = false;
  bool _timelineHydrationRunning = false;
  bool _timelineHydrationRequested = false;
  bool _resumeTimelineRefreshRunning = false;
  bool _resumeTimelineRefreshRequested = false;
  final Map<String, Uint8List> _avatarBytes = {};
  final Map<String, Uri?> _avatarUris = {};
  final Map<String, Uint8List> _notificationAvatarBytes = {};
  final Map<String, Uint8List> _senderAvatarBytes = {};
  final Map<String, Uint8List> _spaceProfileAvatarBytes = {};
  final Map<String, Uint8List> _spaceProfileBannerBytes = {};
  final Map<String, Uint8List> _spaceProfileVoiceBackgroundBytes = {};
  final Map<String, Uri?> _senderAvatarUris = {};
  final Map<String, String> _decryptedPreviews = {};
  final Map<String, ReplyPreview> _replyPreviews = {};
  final Map<String, List<LinkPreview>> _linkPreviews = {};
  final Set<String> _hydratedPollResponseIds = {};
  final LinkPreviewCache _linkPreviewUrlCache = LinkPreviewCache();
  static const _maximumConcurrentStickerPreviewLoads = 4;
  final Queue<_StickerPreviewLoad> _stickerPreviewQueue = Queue();
  final Map<String, Future<Uint8List?>> _stickerPreviewLoads = {};
  int _activeStickerPreviewLoads = 0;
  Timer? _profileRefreshTimer;
  bool _settingsHydrated = false;
  Future<void>? _recoveryInFlight;
  String? _recoveryStage;
  bool _profileRefreshRunning = false;
  final LinkedHashMap<String, _ProfileCacheEntry> _profileCache =
      LinkedHashMap();
  final Map<String, Future<UserProfileSummary>> _profileRequests = {};
  final LinkedHashSet<String> _avatarValidatedEventIds = LinkedHashSet();
  final Set<String> _outboundSessionsReset = {};
  final Set<String> _roomHeroUsersLoaded = {};
  bool _refreshingRoomMetadata = false;
  bool _roomMetadataRefreshRequested = false;
  final Set<String> _roomsMarkingRead = {};
  final Map<String, String> _lastMarkedReadEventIds = {};
  bool _applicationForeground = true;
  bool _desktopIdle = true;
  Timer? _desktopActivityLeaseTimer;
  bool _conversationVisible = false;
  bool _conversationAtPresent = false;
  final Map<String, String?> _firstUnreadEventIds = {};
  final Map<String, String> _lastNotificationEventIds = {};
  final Map<String, DateTime> _lastForegroundAlertAt = {};
  final Map<String, RoomPresentation> _roomPresentationOverrides = {};
  final Map<String, Map<String, dynamic>> _spaceChannelLayoutOverrides = {};
  final Map<String, List<String>> _spaceRoomOrderOverrides = {};
  final Map<String, Set<String>> _collapsedChannelCategories = {};
  final LinkedHashMap<String, List<ChatMessage>> _roomMessageCache =
      LinkedHashMap();
  final Map<String, String> _offlineSendRooms = {};
  final Set<String> _dismissedLocalEchoIds = {};
  final ScheduledMessageStore _scheduledMessageStore = ScheduledMessageStore();
  Timer? _scheduledMessageTimer;
  Timer? _temporaryRoomMuteTimer;
  final Map<String, Timer> _memberTimeoutTimers = {};
  bool _restoringMemberTimeouts = false;
  final Set<String> _bookmarkedEventIds = {};
  final Map<String, DateTime> _temporaryRoomMutes = {};
  final Map<String, RoomNotificationMode> _temporaryRoomMuteRestoreModes = {};
  PresenceMode _presenceMode = PresenceMode.online;
  List<StickerPackSummary> _stickerPacks = const [];
  String? _stickerPackSourceSignature;
  bool _retryingOfflineSends = false;
  bool _notificationsPrimed = false;
  bool _notificationPreviewsEnabled = true;
  AppPreferences _preferences = AppPreferences(
    fontScale: _platformDefaultFontScale,
  );
  AppPreferences? _accountPreferences;
  DeviceAppearanceSnapshot? _deviceAppearance;
  int? _maximumUploadBytes;
  List<DeviceSessionSummary> _deviceSessions = const [];
  bool _devicesLoading = false;
  String? _profileDisplayName;
  Uint8List? _profileAvatarBytes;
  UserPresence _profilePresence = UserPresence.offline;
  String? _profileStatusMessage;
  bool _ownProfileHydrated = false;
  int? _profileColor;
  bool _profileLoading = false;
  int _profileRevision = 0;
  ProfileFieldsCapability? _profileFieldsCapability;
  bool _profileFieldsCapabilityLoaded = false;
  int _storageUsageBytes = 0;
  bool _storageLoading = false;
  final MediaRangeProxy _mediaRangeProxy = MediaRangeProxy();
  final Map<String, MediaPlaybackSource> _mediaPlaybackSources = {};
  final Map<String, int> _mediaPlaybackReferences = {};
  final LinkedHashMap<String, Uint8List> _attachmentBytesCache =
      LinkedHashMap();
  final Map<String, Future<Uint8List>> _attachmentDownloads = {};
  // Cached room rows can mount before their new Timeline has loaded.
  final LinkedHashMap<String, Event> _attachmentEvents = LinkedHashMap();
  int _attachmentBytesCacheSize = 0;
  int _attachmentCacheGeneration = 0;
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
  String? get profileDisplayName {
    final client = _client;
    final userId = client?.userID;
    final spaceId = _selectedSpaceId;
    final override = userId == null || spaceId == null
        ? null
        : client
              ?.getRoomById(spaceId)
              ?.getState(EventTypes.RoomMember, userId)
              ?.content
              .tryGet<String>('displayname');
    return override?.trim().isNotEmpty == true ? override : _profileDisplayName;
  }

  @override
  Uint8List? get profileAvatarBytes {
    final userId = _client?.userID;
    return userId == null
        ? _profileAvatarBytes
        : _senderAvatarBytes['${_selectedRoomId ?? _selectedSpaceId}|$userId'] ??
              _profileAvatarBytes;
  }

  @override
  UserPresence get profilePresence => _profilePresence;
  @override
  String? get profileStatusMessage => _profileStatusMessage;
  @override
  int? get profileColor => _profileColor;
  @override
  bool get profileLoading => _profileLoading;
  @override
  int get profileRevision => _profileRevision;
  @override
  bool get shouldShowFirstRunTour => true;
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
          topic: room.topic,
          muted: room.pushRuleState == PushRuleState.dontNotify,
        ),
      )
      .toList(growable: false);
  @override
  List<ChannelCategorySummary> get selectedSpaceCategories =>
      _channelCategoriesFor(_selectedSpaceId);
  @override
  bool get timelineLoading => _timelineLoading;
  @override
  bool get historyLoading => _historyLoading;
  @override
  bool get canLoadMoreHistory {
    final timeline = _timeline;
    if (timeline == null) return false;
    if (_timelineServerExhausted) return false;
    // The SDK's canRequestHistory flag only describes its own database cursor.
    // Deltiecord also walks its persisted-event cursor before falling back to
    // the room continuation token, so any one signal can still have history.
    return !_timelineDatabaseExhausted ||
        timeline.canRequestHistory ||
        timeline.chunk.prevBatch.isNotEmpty ||
        (timeline.room.prev_batch?.isNotEmpty ?? false);
  }

  @override
  bool get canLoadMoreFuture => _timeline?.canRequestFuture ?? false;
  @override
  bool get atTimelinePresent => !(_timeline?.canRequestFuture ?? false);
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
  bool get voiceDeafened => _voice?.deafened ?? false;
  @override
  bool get voiceCameraEnabled => _voice?.cameraEnabled ?? false;
  @override
  bool get voiceScreenSharing => _voice?.screenSharing ?? false;
  @override
  double get voiceInputLevel => _voice?.inputLevel ?? 0;
  @override
  String? get voiceError => _voice?.error;
  @override
  List<AudioInputSummary> get audioInputs => _voice?.audioInputs ?? const [];
  @override
  String? get selectedAudioInputId => _voice?.selectedAudioInputId;
  @override
  List<RtcDeviceSummary> get audioOutputs => _voice?.audioOutputs ?? const [];
  @override
  String? get selectedAudioOutputId => _voice?.selectedAudioOutputId;
  @override
  List<RtcDeviceSummary> get cameras => _voice?.cameras ?? const [];
  @override
  String? get selectedCameraId => _voice?.selectedCameraId;
  @override
  List<RtcMediaStreamSummary> get rtcMediaStreams =>
      _voice?.mediaStreams ?? const [];
  @override
  List<DeviceSessionSummary> get deviceSessions => _deviceSessions;
  @override
  bool get devicesLoading => _devicesLoading;
  @override
  int get storageUsageBytes => _storageUsageBytes;
  @override
  bool get storageLoading => _storageLoading;
  @override
  List<String> get blockedUserIds => _client?.ignoredUsers ?? const [];
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
    suggestions.insertAll(0, const [
      MentionSuggestion(matrixId: '@everyone', displayName: 'everyone'),
      MentionSuggestion(matrixId: '@all', displayName: 'all'),
    ]);
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
    final roles = _rolesForRoom(room);
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
            nameColor: roles.colorFor(user.id),
            avatarBytes:
                _senderAvatarBytes['${room.id}|${user.id}'] ??
                _senderAvatarBytes[user.id],
            presence: switch (presence) {
              PresenceType.online => UserPresence.online,
              PresenceType.unavailable => UserPresence.away,
              _ => UserPresence.offline,
            },
            powerLevel: user.powerLevel.level,
            membership: user.membership.name,
            canKick:
                room.canKick &&
                user.id != _matrix.userID &&
                user.powerLevel < room.ownPowerLevel,
            canBan:
                room.canBan &&
                user.id != _matrix.userID &&
                user.powerLevel < room.ownPowerLevel,
            canChangePowerLevel:
                room.canChangePowerLevel &&
                user.id != _matrix.userID &&
                user.powerLevel < room.ownPowerLevel,
            maxAssignablePowerLevel: room.ownPowerLevel.level,
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
          (message) => matchesMessageSearch(
            body: message.body,
            sender: message.sender,
            query: normalized,
            senderId: message.senderId,
            roomName: selectedRoom?.name,
            timestamp: message.timestamp,
            attachment: message.attachment,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ChatMessage>> searchRoomHistory(String query) =>
      _searchRoomHistory(query);

  @override
  bool get notificationPreviewsEnabled => _notificationPreviewsEnabled;

  @override
  List<RoomSummary> get rooms {
    final selectedSpaceId = _selectedSpaceId;
    final visible = selectedSpaceId == null
        ? _homeRooms
        : _roomsForSpace(selectedSpaceId);
    final joined = visible.map(_roomSummary).toList(growable: false);
    final ids = joined.map((room) => room.id).toSet();
    return [
      ...joined,
      if (selectedSpaceId != null)
        ...?_discoveredSpaceRooms[selectedSpaceId]?.where(
          (room) => !ids.contains(room.id),
        ),
    ];
  }

  @override
  int get directUnreadCount => _homeRooms
      .where((room) => room.isDirectChat)
      .fold(0, (sum, room) => sum + room.notificationCount);

  @override
  int get serverPingCount => _joinedRooms
      .where((room) => !room.isSpace && !room.isDirectChat)
      .fold(0, (sum, room) => sum + room.highlightCount);

  @override
  int get totalAttentionCount => directUnreadCount + serverPingCount;

  @override
  int pingCountForSpace(String spaceId) =>
      _roomsForSpace(spaceId).fold(0, (sum, room) => sum + room.highlightCount);

  @override
  bool hasUnreadForSpace(String spaceId) => _roomsForSpace(
    spaceId,
  ).any((room) => room.isUnread || room.highlightCount > 0);

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
  RoomNotificationMode get selectedRoomNotificationMode =>
      _notificationModeFor(_client?.getRoomById(_selectedRoomId ?? ''));
  @override
  DateTime? get selectedRoomMutedUntil => _temporaryRoomMutes[_selectedRoomId];

  @override
  List<ChatMessage> get messages {
    if (_timeline != null) return _mappedMessages;
    return _roomMessageCache[_selectedRoomId] ?? const [];
  }

  @override
  List<ChatMessage> get bookmarkedMessages => _roomMessageCache.values
      .expand((messages) => messages)
      .where((message) => _bookmarkedEventIds.contains(message.id))
      .toList(growable: false);

  @override
  String? roomIdForMessage(String eventId) {
    for (final entry in _roomMessageCache.entries) {
      if (entry.value.any((message) => message.id == eventId)) return entry.key;
    }
    return _selectedRoomId;
  }

  @override
  List<ScheduledMessageSummary> get scheduledMessages =>
      _scheduledMessageStore.messages;

  @override
  List<InboxItemSummary> get unifiedInbox => _buildUnifiedInbox();

  @override
  List<StickerPackSummary> get stickerPacks => _stickerPacks;

  @override
  PresenceMode get presenceMode => _presenceMode;

  void _cacheCurrentRoomMessages() {
    final roomId = _selectedRoomId;
    if (roomId == null || _timeline == null) return;
    final snapshot = _mappedMessages;
    _roomMessageCache
      ..remove(roomId)
      ..[roomId] = List.unmodifiable(snapshot);
    while (_roomMessageCache.length > 12) {
      _roomMessageCache.remove(_roomMessageCache.keys.first);
    }
  }

  void _notifyBackendListeners() {
    // Key restoration can emit many synthetic syncs in a single frame. Publish
    // the latest state once per frame-sized window, yielding to browser input.
    _backendUpdates.request();
  }

  @override
  Future<void> enableWebNotifications() async {
    await enableBrowserPush(_matrix);
    if (!_preferences.notificationsEnabled) {
      await updatePreferences(
        _preferences.copyWith(notificationsEnabled: true),
      );
    }
  }

  bool get _mayAdvanceReadMarker =>
      _applicationForeground && _conversationVisible && _conversationAtPresent;

  @override
  void setApplicationForeground(bool foreground) {
    if (_applicationForeground == foreground) {
      if (foreground) _dismissVisibleRoomNotification();
      if (_mayAdvanceReadMarker) unawaited(_markSelectedRoomRead());
      return;
    }
    _applicationForeground = foreground;
    // View focus can arrive after the lifecycle-resumed callback. Refresh on
    // this actual foreground transition too, rather than losing that wakeup.
    if (foreground) unawaited(_refreshTimelineAfterResume());
    if (foreground) _dismissVisibleRoomNotification();
    if (foreground && Platform.isAndroid) {
      unawaited(_restoreUnifiedPushPusher());
    }
    if (_mayAdvanceReadMarker) unawaited(_markSelectedRoomRead());
  }

  @override
  void refreshApplicationState() {
    _dismissVisibleRoomNotification();
    // Account-data settings are applied by the authoritative /sync listener.
    // Re-reading the SDK cache on resume can resurrect the value from before
    // a recent write and make theme changes appear stuck until restart.
    if (Platform.isAndroid) {
      unawaited(_restoreUnifiedPushPusher());
    }
    if (_applicationForeground) unawaited(_refreshTimelineAfterResume());
    _notifyBackendListeners();
  }

  @override
  void setDesktopIdle(bool idle) => _setDesktopIdle(idle);

  @override
  void setConversationVisible(bool visible) {
    _conversationVisible = visible;
    _dismissVisibleRoomNotification();
    if (_mayAdvanceReadMarker) unawaited(_markSelectedRoomRead());
  }

  void _dismissVisibleRoomNotification() {
    final roomId = _selectedRoomId;
    // Dismissal is about what is visible, not whether history is scrolled to
    // the newest event. Read receipts retain their stricter at-present guard.
    if (_applicationForeground && _conversationVisible && roomId != null) {
      InAppNotificationCenter.dismissRoom(roomId);
      unawaited(_notifications.clearRoom(roomId));
    }
  }

  @override
  void setConversationAtPresent(bool atPresent) {
    if (_conversationAtPresent == atPresent) return;
    _conversationAtPresent = atPresent;
    if (_mayAdvanceReadMarker) unawaited(_markSelectedRoomRead());
  }

  @override
  Future<void> initialize() => _initializeSession();

  /// Resolves a privacy-preserving Matrix push hint inside the logged-in
  /// client, after the event and any room key have reached the local store.
  Future<Map<String, Object?>?> resolveAndroidPush(
    String roomId,
    String eventId,
  ) => resolveAndroidPushNotification(
    _matrix,
    roomId,
    eventId,
    avatarPool: _avatarMediaPool,
  );

  Future<void> openAndroidPushTarget(NotificationTarget target) =>
      _openNotificationTarget(target);

  Future<bool> performAndroidPushAction(
    String roomId,
    String eventId,
    String action,
    String? reply,
  ) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) return false;
    try {
      switch (action) {
        case 'reply':
          final body = reply?.trim() ?? '';
          if (body.isEmpty) return false;
          await _sendMessage(body, roomId: roomId, replyToMessageId: eventId);
        case 'read':
          await room.setReadMarker(eventId, mRead: eventId);
        case 'mute':
          await _setRoomNotificationMode(roomId, RoomNotificationMode.muted);
        default:
          return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

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
  Future<void> registerDeltiecordAccount({
    required String username,
    required String password,
  }) => _registerDeltiecordAccount(username: username, password: password);

  @override
  Future<void> logout() => _logoutSession();

  @override
  Future<void> refreshAudioInputs() => _refreshAudioInputs();

  @override
  Future<void> selectAudioInput(String? deviceId) =>
      _selectAudioInput(deviceId);

  @override
  Future<void> selectAudioOutput(String? deviceId) =>
      _selectAudioOutputAndRemember(deviceId);

  @override
  Future<void> selectCamera(String? deviceId) =>
      _selectCameraAndRemember(deviceId);

  @override
  Future<void> refreshDevices() => _refreshDevices();

  @override
  Future<void> refreshProfile() => _refreshProfile();

  @override
  Future<void> setProfileDisplayName(String displayName) =>
      _setProfileDisplayName(displayName);

  @override
  Future<void> setProfileAvatar(
    Uint8List? bytes, {
    String fileName = 'avatar.png',
    String mimeType = 'image/png',
  }) => _setProfileAvatar(bytes, fileName: fileName, mimeType: mimeType);

  @override
  Future<void> removeDevice(String deviceId, String password) =>
      _removeDevice(deviceId, password);

  @override
  Future<void> requestDeviceVerification(String deviceId) =>
      _requestDeviceVerification(deviceId);

  @override
  Future<void> deleteAccount(String password) => _deleteAccount(password);

  @override
  Future<void> changeAccountPassword(
    String currentPassword,
    String newPassword,
  ) => _matrix.changePassword(newPassword, oldPassword: currentPassword);

  @override
  Future<void> joinVoiceRoom(String roomId) => _joinVoiceRoom(roomId);

  @override
  Future<void> setVoiceMuted(bool muted) => _setVoiceMuted(muted);

  @override
  Future<void> setVoiceDeafened(bool deafened) =>
      _voice?.setDeafened(deafened) ?? Future.value();

  @override
  Future<void> setVoiceCameraEnabled(bool enabled) =>
      _voice?.setCameraEnabled(enabled) ?? Future.value();

  @override
  Future<void> setVoiceScreenSharing(bool enabled) =>
      _voice?.setScreenSharing(enabled) ?? Future.value();

  @override
  Future<void> setParticipantVolume(String userId, double volume) =>
      _setParticipantVolumeAndRemember(userId, volume);

  @override
  Future<void> setParticipantLocallyMuted(String userId, bool muted) =>
      _voice?.setParticipantLocallyMuted(userId, muted) ?? Future.value();

  @override
  Future<void> leaveVoiceRoom() => _leaveVoiceRoom();

  @override
  Future<void> setComposerTyping(bool typing) => _setComposerTyping(typing);

  @override
  Future<void> setNotificationPreviewsEnabled(bool enabled) =>
      _setNotificationPreviewsEnabled(enabled);

  @override
  Future<void> setUnifiedPushEndpoint(String endpoint) =>
      _setUnifiedPushEndpoint(endpoint);

  @override
  Future<String> reconcileUnifiedPushEndpoint(String endpoint) =>
      _reconcileUnifiedPushEndpoint(endpoint);

  @override
  Future<void> removeUnifiedPushEndpoint(String endpoint) =>
      _removeUnifiedPushEndpoint(endpoint);

  @override
  Future<void> updatePreferences(AppPreferences preferences) =>
      _updatePreferences(preferences);

  @override
  Future<SpaceAdministration> getSpaceAdministration(String spaceId) =>
      _getSpaceAdministration(spaceId);
  final Map<String, List<RoomSummary>> _discoveredSpaceRooms = {};
  final Set<String> _discoveringSpaces = {};
  final Map<String, SpaceRoles> _reviewedSpaceRoles = {};
  String? _roleProfileSignature;
  @override
  Future<RoomAccessSettings> getRoomAccessSettings(String roomId) =>
      _getRoomAccessSettings(roomId);
  @override
  Future<void> setRoomAccess(
    String roomId,
    String joinRule, {
    String? spaceId,
  }) => _setRoomAccess(roomId, joinRule, spaceId: spaceId);
  @override
  Future<void> setRoomHistoryVisibility(String roomId, String value) =>
      _setRoomHistoryVisibility(roomId, value);
  @override
  Future<void> setRoomDiscoverable(String roomId, bool value) =>
      _matrix.setRoomVisibilityOnDirectory(
        roomId,
        visibility: value ? Visibility.public : Visibility.private,
      );
  @override
  Future<void> setSpacePolicy(
    String spaceId, {
    required String defaultChannelAccess,
    required Map<String, bool> eventVisibility,
  }) => _setSpacePolicy(spaceId, defaultChannelAccess, eventVisibility);
  @override
  Object? spaceAdministrationRevision(String spaceId) {
    final space = _client?.getRoomById(spaceId);
    if (space == null) return null;
    return jsonEncode([
      space.getState(spaceRolesEventType)?.content,
      for (final id in {
        spaceId,
        ...space.spaceChildren.map((child) => child.roomId).whereType<String>(),
      })
        [
          id,
          _client
              ?.getRoomById(id)
              ?.getState(EventTypes.RoomPowerLevels)
              ?.content,
        ],
    ]);
  }

  @override
  String? get selectedRoomSpaceId {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    return room == null ? _selectedSpaceId : _spaceForRoom(room)?.id;
  }

  @override
  Future<Map<String, String>> getBannedMembers(String roomId) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('Join this room first.');
    final members = await room.requestParticipants(
      [Membership.ban],
      false,
      false,
      true,
    );
    return {for (final member in members) member.id: member.calcDisplayname()};
  }

  @override
  Future<void> unbanRoomMember(String roomId, String userId) =>
      _matrix.unban(roomId, userId);
  @override
  Future<void> saveSpaceRoles(
    String spaceId,
    SpaceRoles roles, {
    SpaceRoles? expected,
  }) => _saveSpaceRoles(spaceId, roles, expected: expected);
  @override
  Future<void> applySpaceRolePower(
    String spaceId,
    String roomId,
    SpaceRoles reviewedRoles,
  ) => _applySpaceRolePower(spaceId, roomId, reviewedRoles);
  @override
  Future<void> setAdministrationRule(
    String roomId,
    AdministrationRule rule,
    int level,
  ) => _setAdministrationRule(roomId, rule, level);

  @override
  Future<void> setAppearanceSync(
    bool enabled, {
    bool useDeviceAppearance = true,
  }) => _setAppearanceSync(enabled, useDeviceAppearance: useDeviceAppearance);

  @override
  Future<Uri> resolveLinkPreviewVideo(Uri pageUrl, Uri cachedVideoUrl) =>
      _resolvePlayableLinkVideo(pageUrl, cachedVideoUrl);

  @override
  void clearError() => _clearSessionError();
  @override
  Future<void> refreshEncryptionSetup() => _refreshEncryptionSetup();

  @override
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase) =>
      _recoveryInFlight ??= _recoverEncryption(
        recoveryKeyOrPassphrase,
      ).whenComplete(() => _recoveryInFlight = null);

  @override
  String? get encryptionRecoveryStage => _recoveryStage;

  @override
  Future<String> createEncryptionSetup() => _createEncryptionSetup();

  @override
  Future<String> regenerateEncryptionRecoveryKey() =>
      _regenerateEncryptionRecoveryKey();
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
    String topic = '',
    bool encrypted = true,
  }) => _createRoom(
    name: name,
    presentation: presentation,
    topic: topic,
    encrypted: encrypted,
  );

  @override
  Future<void> createSpace({required String name, String topic = ''}) =>
      _createSpace(name: name, topic: topic);
  @override
  Future<void> createChannelCategory(String name) =>
      _createChannelCategory(name);
  @override
  Future<void> renameChannelCategory(String categoryId, String name) =>
      _renameChannelCategory(categoryId, name);
  @override
  Future<void> deleteChannelCategory(String categoryId) =>
      _deleteChannelCategory(categoryId);
  @override
  Future<void> reorderChannelCategory(String categoryId, int newIndex) =>
      _reorderChannelCategory(categoryId, newIndex);
  @override
  Future<void> setChannelCategoryCollapsed(String categoryId, bool collapsed) =>
      _setChannelCategoryCollapsed(categoryId, collapsed);
  @override
  Future<void> moveRoomInSpace(
    String roomId, {
    String? categoryId,
    String? beforeRoomId,
  }) => _moveRoomInSpace(
    roomId,
    categoryId: categoryId,
    beforeRoomId: beforeRoomId,
  );

  @override
  int spaceChannelLayoutPowerLevel(String spaceId) =>
      _spaceChannelLayoutPowerLevel(spaceId);

  @override
  bool canManageSpaceChannelLayout(String spaceId) =>
      _canManageSpaceChannelLayout(spaceId);

  @override
  bool canSetSpaceChannelLayoutPowerLevel(String spaceId) =>
      _matrix.getRoomById(spaceId)?.canChangePowerLevel ?? false;

  @override
  Future<void> setSpaceChannelLayoutPowerLevel(
    String spaceId,
    int powerLevel,
  ) => _setSpaceChannelLayoutPowerLevel(spaceId, powerLevel);

  @override
  Future<void> renameRoom(String roomId, String name) =>
      _renameRoom(roomId, name);

  @override
  Future<void> setRoomTopic(String roomId, String topic) =>
      _setRoomTopic(roomId, topic);

  @override
  Future<void> setRoomAvatar(String roomId, Uint8List? bytes) =>
      _setRoomAvatar(roomId, bytes);

  @override
  Future<void> leaveRoom(String roomId) => _leaveRoom(roomId);

  @override
  Future<void> setRoomMuted(String roomId, bool muted) =>
      _setRoomMuted(roomId, muted);

  @override
  Future<void> setMemberPowerLevel(String userId, int powerLevel) =>
      _setMemberPowerLevel(userId, powerLevel);

  @override
  Future<void> kickMember(String userId, {String? reason}) =>
      _moderateMember(userId, _MemberModerationAction.kick, reason: reason);

  @override
  Future<void> banMember(String userId, {String? reason}) =>
      _moderateMember(userId, _MemberModerationAction.ban, reason: reason);

  @override
  Future<void> timeoutMember(String userId, DateTime until) =>
      _timeoutMember(userId, until);

  @override
  Future<void> unbanMember(String userId) =>
      _moderateMember(userId, _MemberModerationAction.unban);

  @override
  Future<void> inviteMember(String userId, {String? reason}) =>
      _inviteMember(userId, reason: reason);
  @override
  Future<void> acceptRoomInvite(String roomId) => _acceptRoomInvite(roomId);
  @override
  Future<void> rejectRoomInvite(String roomId) => _rejectRoomInvite(roomId);
  @override
  Future<void> approveKnock(String userId) => _inviteMember(userId);

  @override
  Future<void> rejectKnock(String userId) => _moderateMember(
    userId,
    _MemberModerationAction.kick,
    reason: 'Join request declined',
  );

  @override
  Future<List<String>> getRoomAliases(String roomId) => _getRoomAliases(roomId);

  @override
  Future<void> addRoomAlias(String roomId, String alias) =>
      _matrix.setRoomAlias(alias, roomId);

  @override
  Future<void> deleteRoomAlias(String alias) => _matrix.deleteRoomAlias(alias);

  @override
  Future<void> setRoomCanonicalAlias(String roomId, String? alias) =>
      _setRoomCanonicalAlias(roomId, alias);

  @override
  Future<void> refreshStorageUsage() => _refreshStorageUsage();

  @override
  Future<void> clearMediaCache() => _clearMediaCache();

  @override
  Future<UserProfileSummary> getUserProfile(
    String userId, {
    bool refresh = false,
  }) => _getUserProfile(userId, refresh: refresh);

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
  }) => _updateOwnProfileFields(
    bio: bio,
    pronouns: pronouns,
    timezone: timezone,
    statusMessage: statusMessage,
    profileColor: profileColor,
    profileColorSecondary: profileColorSecondary,
    bannerBytes: bannerBytes,
    removeBanner: removeBanner,
  );

  @override
  Future<void> updateOwnVoicePresentation({
    int? color,
    Uint8List? backgroundBytes,
    bool removeColor = false,
    bool removeBackground = false,
  }) => _updateOwnVoicePresentation(
    color: color,
    backgroundBytes: backgroundBytes,
    removeColor: removeColor,
    removeBackground: removeBackground,
  );

  @override
  Future<List<SpaceDirectoryEntry>> searchPublicSpaces(String query) =>
      _searchPublicSpaces(query);

  @override
  Future<void> joinPublicSpace(String roomId) => _joinPublicSpace(roomId);

  @override
  Future<void> startDirectChat(String userId) => _startDirectChat(userId);

  @override
  Future<void> setUserBlocked(String userId, bool blocked) =>
      _setUserBlocked(userId, blocked);

  @override
  Future<void> setSelectedRoomMuted(bool muted) => _setSelectedRoomMuted(muted);
  @override
  Future<void> setRoomNotificationMode(
    String roomId,
    RoomNotificationMode mode,
  ) => _setRoomNotificationMode(roomId, mode);
  @override
  Future<void> muteRoomUntil(String roomId, DateTime? until) =>
      _muteRoomUntil(roomId, until);
  @override
  Future<void> markRoomUnread(String roomId, bool unread) =>
      _markRoomUnread(roomId, unread);
  @override
  Future<void> loadMoreHistory({String? anchorEventId}) =>
      _loadMoreHistory(anchorEventId: anchorEventId);
  @override
  Future<void> loadMoreFuture({String? anchorEventId}) =>
      _loadMoreFuture(anchorEventId: anchorEventId);
  @override
  Future<List<ChatMessage>> loadPinnedMessages() => _loadPinnedMessages();
  @override
  Future<void> toggleMessagePinned(String messageId) =>
      _toggleMessagePinned(messageId);
  @override
  Future<void> toggleMessageBookmarked(String messageId) =>
      _toggleMessageBookmarked(messageId);
  @override
  Future<void> jumpToPresent() => _jumpToPresent();
  @override
  Future<void> jumpToEvent(String eventId) => _jumpToEvent(eventId);

  @override
  Future<void> sendMessage(
    String body, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) => _sendMessage(
    body,
    roomId: roomId,
    formattedBody: formattedBody,
    replyToMessageId: replyToMessageId,
    editMessageId: editMessageId,
  );

  @override
  Future<void> scheduleMessage(
    String text,
    DateTime sendAt, {
    String? roomId,
    String? replyToMessageId,
  }) => _scheduleMessage(
    text,
    sendAt,
    roomId: roomId,
    replyToMessageId: replyToMessageId,
  );

  @override
  Future<void> cancelScheduledMessage(String scheduledMessageId) =>
      _cancelScheduledMessage(scheduledMessageId);

  @override
  Future<void> sendPoll(PollDraft poll, {String? roomId}) =>
      _sendPoll(poll, roomId: roomId);

  @override
  Future<void> answerPoll(String messageId, List<String> answerIds) =>
      _answerPoll(messageId, answerIds);

  @override
  Future<void> endPoll(String messageId) => _endPoll(messageId);

  @override
  Future<void> sendSticker(StickerSummary sticker, {String? roomId}) =>
      _sendSticker(sticker, roomId: roomId);

  @override
  Future<void> refreshStickerPacks() => _refreshStickerPacks();
  @override
  Future<StickerPackSummary?> resolveStickerPack({
    String? packId,
    Uri? mediaUri,
  }) => _resolveStickerPack(packId: packId, mediaUri: mediaUri);

  @override
  Future<Uint8List?> loadStickerPreview(StickerSummary sticker) =>
      _loadStickerPreview(sticker);

  @override
  Future<void> savePersonalStickerPack(StickerPackDraft pack) =>
      _savePersonalStickerPack(pack);

  @override
  bool canManageStickerPacksInRoom(String roomId) =>
      _canManageStickerPacksInRoom(roomId);

  @override
  Future<void> saveRoomStickerPack(String roomId, StickerPackDraft pack) =>
      _saveRoomStickerPack(roomId, pack);

  @override
  Future<void> publishPersonalStickerPack(
    StickerPackSummary pack,
    String roomId,
  ) => _publishPersonalStickerPack(pack, roomId);

  @override
  Future<void> deleteStickerPack(StickerPackSummary pack) =>
      _deleteStickerPack(pack);

  @override
  Future<void> replaceStickerPack(
    StickerPackSummary existing,
    StickerPackDraft replacement,
  ) => _replaceStickerPack(existing, replacement);

  @override
  Future<void> setStickerPackGloballyEnabled(
    StickerPackSummary pack,
    bool enabled,
  ) => _setStickerPackGloballyEnabled(pack, enabled);

  @override
  Future<void> setPresenceMode(PresenceMode mode) => _setPresenceMode(mode);

  @override
  Future<SpacePagesSummary> getSpacePages(String spaceId) =>
      _getSpacePages(spaceId);

  @override
  Future<void> setSpacePages(String spaceId, SpacePagesSummary pages) =>
      _setSpacePages(spaceId, pages);

  @override
  Future<SpaceProfileOverride?> getSpaceProfileOverride(String spaceId) =>
      _getSpaceProfileOverride(spaceId);

  @override
  Future<void> setSpaceProfileOverride(SpaceProfileOverride profile) =>
      _setSpaceProfileOverride(profile);

  @override
  Future<void> redactMessage(String messageId) => _redactMessage(messageId);

  @override
  Future<void> retryMessage(String messageId) => _retryMessage(messageId);

  @override
  Future<void> cancelPendingMessage(String messageId) =>
      _cancelPendingMessage(messageId);

  @override
  Future<void> toggleReaction(
    String messageId,
    String key, {
    CustomEmojiReference? customEmoji,
  }) => _toggleReaction(messageId, key, customEmoji: customEmoji);
  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) => _sendAttachment(
    attachment,
    roomId: roomId,
    replyToMessageId: replyToMessageId,
  );

  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) => _downloadAttachment(messageId, thumbnail: thumbnail);

  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) =>
      _getMediaPlaybackSource(messageId);

  @override
  Future<void> releaseMediaPlaybackSource(String messageId) async =>
      _releaseMediaPlaybackSource(messageId);

  @override
  Future<String?> getAttachmentReference(String messageId) async =>
      _getAttachmentReference(messageId);

  Future<void> _closeTimeline() async {
    _forumRoots.clear();
    _forumCursor = null;
    _forumHasMore = true;
    _forumLoading = false;
    for (final session in _threadSessions.toList()) {
      session.dispose();
    }
    _timelineGeneration++;
    _timelineHydrationRequested = false;
    _timeline?.cancelSubscriptions();
    _timeline = null;
    _timelineDatabaseOffset = 0;
    _timelineDatabaseExhausted = false;
    _timelineServerExhausted = false;
    _replyPreviews.clear();
    _linkPreviews.clear();
    _hydratedPollResponseIds.clear();
    for (final source in _mediaPlaybackSources.values) {
      releaseBrowserMediaUrl(source.uri);
    }
    _mediaPlaybackSources.clear();
    _mediaPlaybackReferences.clear();
    _mediaRangeProxy.clear();
  }

  String _friendlyError(Object exception) {
    return safeErrorMessage(exception);
  }

  void _debugRoomOpenTiming(String message) {
    if (const bool.fromEnvironment('dart.vm.product')) return;
    developer.log(message, name: 'deltiecord.room_open');
  }

  @override
  void dispose() {
    _browserAuthenticationCanceled = true;
    final authBrowser = _activeAuthBrowser;
    if (authBrowser != null) unawaited(authBrowser.close());
    for (final session in _threadSessions.toList()) {
      session.dispose();
    }
    _backendUpdates.dispose();
    _typingStopTimer?.cancel();
    _settingsSaveTimer?.cancel();
    _desktopActivityLeaseTimer?.cancel();
    _scheduledMessageTimer?.cancel();
    _temporaryRoomMuteTimer?.cancel();
    for (final timer in _memberTimeoutTimers.values) {
      timer.cancel();
    }
    _memberTimeoutTimers.clear();
    _stopProfileRefreshTimer();
    _profileCache.clear();
    _profileRequests.clear();
    _attachmentBytesCache.clear();
    _attachmentDownloads.clear();
    _attachmentEvents.clear();
    _attachmentBytesCacheSize = 0;
    _attachmentCacheGeneration++;
    final voice = _voice;
    _voice = null;
    voice?.removeListener(notifyListeners);
    voice?.dispose();
    _timeline?.cancelSubscriptions();
    _syncSubscription?.cancel();
    _loginSubscription?.cancel();
    _syncStatusSubscription?.cancel();
    _notificationSubscription?.cancel();
    _unifiedPushSubscription?.cancel();
    _client?.dispose();
    unawaited(_notifications.dispose());
    unawaited(_mediaRangeProxy.close());
    unawaited(_avatarMediaPool.clear(disk: false));
    _offlineSendRooms.clear();
    _dismissedLocalEchoIds.clear();
    super.dispose();
  }
}

final class _StickerPreviewLoad {
  const _StickerPreviewLoad(this.sticker, this.completer);

  final StickerSummary sticker;
  final Completer<Uint8List?> completer;
}
