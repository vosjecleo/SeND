import 'dart:async';
import '../models/rtc_connectivity.dart';
import '../services/rtc_audio_controls.dart';
import '../services/attachment_text.dart';
import '../services/attachment_admission.dart';
import '../services/queued_message.dart';
import '../services/dm_call_history.dart';
import '../services/encoded_image_dimensions.dart';
import '../services/video_preparation.dart';
import '../models/user_activity.dart';
import '../services/activity_candidate.dart';
import '../services/activity_controller.dart';
import '../services/pack_reorganization.dart';
import '../services/socks_proxy.dart';
import '../services/personal_data.dart';
import '../services/history_index.dart';
import '../services/history_download.dart';
import '../services/history_gap_recovery.dart';
import '../services/history_scope.dart';
import '../services/server_storage.dart';
import '../services/image_preparation.dart';
import '../services/image_animation.dart';
import '../services/upload_labels.dart';
import '../services/frame_diagnostics.dart';
import '../services/activity_service_error.dart';
import '../services/settings_echo_guard.dart';
import '../services/settings_writer.dart';
import '../services/session_scope.dart';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import '../services/platform_io.dart';
import '../services/presence_policy.dart';
import '../services/room_read_marker.dart';
import '../services/browser_lifecycle.dart' as browser;
import '../services/browser_media.dart';
import '../services/browser_push.dart';
import '../services/browser_push_previews.dart';
import '../services/gif_service.dart';
import '../services/notification_volume.dart';
import '../services/notification_avatar.dart';
import '../services/room_mentions.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, listEquals;

import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';
import '../backend/chat_backend.dart';
import '../backend/thread_session.dart';
import '../backend/conversation_send_target.dart';
import '../models/forum_post.dart';
import '../models/login_methods.dart';
import '../services/auth_browser.dart';
import '../services/auth_callback.dart';
import '../models/chat_models.dart';
import '../models/media_compression.dart';
import '../models/room_event_visibility.dart';
import '../services/receipt_positions.dart';
import '../models/space_administration.dart';
import '../services/chat_notifications.dart';
import '../services/favourite_reactions_store.dart';
import '../services/custom_emoji.dart';
import '../services/avatar_media_pool.dart';
import '../services/coalesced_callback.dart';
import '../services/conversation_history_cache.dart';
import '../services/device_appearance_store.dart';
import '../services/device_preferences_store.dart';
import '../services/preference_scopes.dart';
import '../services/account_settings_sync.dart';
import '../services/app_sounds.dart';
import '../services/android_push_bridge.dart';
import '../services/font_preferences.dart';
import '../services/message_search.dart';
import '../services/message_links.dart';
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
import '../services/unavailable_history.dart';
import 'matrix_client_factory.dart';
import 'sized_matrix_file.dart';
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
part 'matrix_history_download.dart';
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
  ActivityController? _activities;
  @override
  ActivitySettings get activitySettings =>
      _activities?.settings ?? const ActivitySettings();
  @override
  List<ActivityCandidate> get detectedApplications =>
      _activities?.candidates ?? const [];
  @override
  String? get activityWarning => _activities?.warning;
  @override
  bool get supportsActivityDetection =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows);
  @override
  UserActivity? activityFor(String userId) => _activities?.activityFor(userId);
  @override
  void Function() watchActivity(
    String userId, {
    required bool Function() isVisible,
  }) => _activities?.watchUser(userId, isVisible) ?? () {};
  @override
  List<UserActivity> activitiesFor(String userId) =>
      _activities?.activitiesFor(userId).live ?? const [];
  @override
  LastFmTrack? lastFmRecentFor(String userId) =>
      _activities?.lastFmRecentFor(userId);
  @override
  void Function() watchListeningHistory(String userId) =>
      _activities?.watchHistory(userId) ?? () {};

  bool _activityVisibleFor(String id) {
    if (id == _client?.userID) {
      return _preferences.sharePresence &&
          _presenceMode != PresenceMode.invisible &&
          _connectionStatus != ConnectionStatus.offline &&
          (supportsActivityDetection || _applicationForeground);
    }
    return _matrixPresenceFor(
          id,
          _profileCache[id]?.profile.presence ?? UserPresence.offline,
        ) !=
        UserPresence.offline;
  }

  @override
  Future<Uint8List?> loadActivityIcon(Uri uri) => _avatarMedia(uri, 384);
  @override
  Future<void> updateActivitySettings(ActivitySettings value) async =>
      _activities?.update(value);

  void _startActivities() {
    if (_activities != null || _client?.userID == null) return;
    unawaited(_startPersonalData());
    unawaited(openHistoryIndex());
    final client = _matrix;
    final ownId = client.userID!;
    final activityField = activityDeviceField(client.deviceID!);
    Future<void> writeRecord(Map<String, Object?>? record) async {
      if (!client.isLogged()) {
        throw const ActivityServiceError('M_UNKNOWN_TOKEN');
      }
      try {
        if (record == null) {
          await client.deleteProfileField(ownId, activityField);
        } else {
          await client.setProfileField(ownId, activityField, {
            activityField: record,
          });
        }
      } on MatrixException catch (error) {
        if (record == null && error.errcode == 'M_NOT_FOUND') return;
        throw ActivityServiceError(
          error.errcode,
          retryAfter: error.retryAfterMs == null
              ? null
              : Duration(milliseconds: error.retryAfterMs!),
        );
      }
    }

    final controller = ActivityController(
      userId: ownId,
      deviceId: client.deviceID!,
      read: (id) async {
        try {
          final fields = (await client.getUserProfile(
            id,
            maxCacheAge: Duration.zero,
          )).additionalProperties;
          return {
            'devices': {
              for (final entry in fields.entries)
                if (entry.key == activityProfileField ||
                    entry.key.startsWith(activityDevicePrefix) ||
                    entry.key.startsWith(lastFmHistoryPrefix))
                  entry.key: entry.value,
            },
          };
        } on MatrixException catch (error) {
          if (error.errcode == 'M_NOT_FOUND' ||
              error.response?.statusCode == 404) {
            return null;
          }
          throw ActivityServiceError(
            error.errcode,
            retryAfter: error.retryAfterMs == null
                ? null
                : Duration(milliseconds: error.retryAfterMs!),
          );
        }
      },
      write: (activity) => writeRecord(activity?.toJson()),
      writeProfile: writeRecord,
      writeHistory: (record) async {
        final field = lastFmHistoryField(client.deviceID!);
        try {
          if (record == null) {
            await client.deleteProfileField(ownId, field);
          } else {
            await client.setProfileField(ownId, field, {field: record});
          }
        } on MatrixException catch (error) {
          if (record == null && error.errcode == 'M_NOT_FOUND') return;
          throw ActivityServiceError(
            error.errcode,
            retryAfter: error.retryAfterMs == null
                ? null
                : Duration(milliseconds: error.retryAfterMs!),
          );
        }
      },
      upload: (bytes) => client.uploadContent(
        bytes,
        filename: 'activity-icon.png',
        contentType: 'image/png',
      ),
      canShare: () => _activityVisibleFor(ownId),
      canView: _activityVisibleFor,
      isForeground: () => _applicationForeground,
    );
    _activities = controller;
    controller.addListener(_notifyBackendListeners);
    unawaited(controller.start());
  }

  Future<void> _stopActivities({bool clear = false}) async {
    final controller = _activities;
    _activities = null;
    if (controller == null) return;
    controller.removeListener(_notifyBackendListeners);
    await controller.close(clear: clear);
  }

  final Set<_MatrixThreadSession> _threadSessions = {};
  ConversationHistoryCache? _threadHistory;
  ConversationHistoryCache _threadHistoryFor(Client client) {
    if (!identical(_threadHistory?.owner, client)) {
      _threadHistory?.dispose();
      _threadHistory = ConversationHistoryCache(
        owner: client,
        read: () async => (await client.database.getCustomCacheObject(
          'send.conversation_history.v1',
        ))?.content,
        write: (data) => client.database.cacheCustomObject(
          'send.conversation_history.v1',
          data,
        ),
      );
    }
    return _threadHistory!;
  }

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
  Future<void> editForumPost(
    String roomId,
    String messageId,
    ForumPost post,
    String body, {
    AttachmentDraft? cover,
    bool removeCover = false,
  }) async {
    final checked = ForumPost.validated(post.title, post.tags);
    final room = _matrix.getRoomById(roomId);
    if (room == null ||
        room.membership != Membership.join ||
        _presentationFor(room) != RoomPresentation.forum) {
      throw StateError('This forum is unavailable.');
    }
    final event = _eventById(messageId) ?? await room.getEventById(messageId);
    if (event == null ||
        event.room.id != roomId ||
        event.senderId != _matrix.userID ||
        event.type != EventTypes.Message ||
        event.redacted ||
        !messageId.startsWith(r'$')) {
      throw StateError('You can only edit your own sent posts.');
    }
    if (body.trim().isEmpty) {
      throw const FormatException('Write a post before saving.');
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
        editMessageId: messageId,
        additionalContent: {forumPostKey: checked.toJson()},
      );
    } else {
      final timeline = _timeline;
      final displayed = timeline == null
          ? event
          : event.getDisplayEvent(timeline);
      final content = removeCover
          ? <String, dynamic>{'msgtype': MessageTypes.Text}
          : Map<String, dynamic>.from(displayed.content);
      content
        ..remove('m.new_content')
        ..remove('m.relates_to')
        ..remove('formatted_body')
        ..remove('format')
        ..['body'] = '${checked.title}\n\n${body.trim()}'
        ..[forumPostKey] = checked.toJson();
      await room.sendEvent(content, editEventId: messageId);
    }
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
    this._client,
    ChatNotificationSink? notifications,
    DirectLinkPreviewFetcher? directPreviewFetcher,
    AvatarMediaPool? avatarMediaPool,
    DeviceAppearanceStore? deviceAppearanceStore,
    DevicePreferencesStore? devicePreferencesStore,
    HistoryIndex Function(String account)? historyIndexFactory,
  }) : _notifications = notifications ?? const SilentChatNotificationSink(),
       _directPreviewFetcher =
           directPreviewFetcher ?? DirectLinkPreviewFetcher(),
       _avatarMediaPool = avatarMediaPool ?? AvatarMediaPool(),
       _historyIndexFactory =
           historyIndexFactory ?? ((account) => HistoryIndex(account)),
       _deviceAppearanceStore =
           deviceAppearanceStore ?? DeviceAppearanceStore(),
       _devicePreferencesStore =
           devicePreferencesStore ?? DevicePreferencesStore();

  final ChatNotificationSink _notifications;
  String? _notificationError;
  @override
  String? get notificationError => _notificationError;
  @override
  Future<void> testSystemNotification() async {
    try {
      await _notifications.initialize();
      await _notifications.show(
        title: 'SeND notification test',
        body: 'System notifications are working.',
        roomId: _selectedRoomId ?? '',
        eventId: '',
        sound: _preferences.notificationSound,
      );
      _notificationError = null;
    } catch (_) {
      _notificationError =
          'System notification registration or delivery failed. Check SeND in system notification settings and retry.';
      rethrow;
    } finally {
      _notifyBackendListeners();
    }
  }

  final DirectLinkPreviewFetcher _directPreviewFetcher;
  final AvatarMediaPool _avatarMediaPool;
  final DeviceAppearanceStore _deviceAppearanceStore;
  final DevicePreferencesStore _devicePreferencesStore;
  Map<String, Object?>? _devicePreferences;
  bool _devicePreferencesLoadFailed = false;
  bool _devicePreferencesLoaded = false;
  int _devicePreferencesRevision = 0;
  String get _preferencesPlatform =>
      '${kIsWeb ? 'web_' : ''}${defaultTargetPlatform.name}';
  String get _platformPreferencesType =>
      '${MatrixBackend._settingsAccountDataType}.platform.$_preferencesPlatform';
  final _platformSettingsEchoGuard = SettingsEchoGuard();
  final HistoryIndex Function(String account) _historyIndexFactory;
  UploadLabels? _uploadLabels;
  Future<UploadLabels?>? _openingUploadLabels;
  final _labelledEvents = <String>{};
  @override
  String? get serverStorageWarning => _uploadLabels?.warning;
  @override
  String? get localStorageWarning => _scheduledMessageStore.warning;
  Future<UploadLabels?> _openUploadLabels() {
    final client = _client;
    if (client == null ||
        client.userID == null ||
        client.homeserver == null ||
        client.accessToken == null) {
      return Future.value();
    }
    if (_uploadLabels?.account == client.userID) {
      return Future.value(_uploadLabels);
    }
    return _openingUploadLabels ??= (() async {
      final service = ServerStorageClient(
        client.httpClient,
        client.homeserver!,
        client.accessToken!,
      );
      final labels = UploadLabels(client.userID!, (rows) async {
        if (!identical(client, _client)) throw StateError('Session changed.');
        if (!_preferences.shareUploadCategories) {
          throw StateError('Upload categorization is disabled.');
        }
        await service.call('labels', {'items': rows});
      });
      await labels.open();
      if (!identical(client, _client)) return null;
      return _uploadLabels = labels;
    })().whenComplete(() => _openingUploadLabels = null);
  }

  Future<void> _recordUploadLabel(Event event) async {
    if (!_preferences.shareUploadCategories) return;
    if (event.type == EventTypes.Sticker ||
        event.senderId != _client?.userID ||
        !event.hasAttachment ||
        !_labelledEvents.add(event.eventId)) {
      return;
    }
    while (_labelledEvents.length > 4096) {
      _labelledEvents.remove(_labelledEvents.first);
    }
    final file = event.content.tryGetMap<String, Object?>('file');
    final reference = file?['url'] ?? event.content['url'];
    if (reference is! String) return;
    final uri = Uri.tryParse(reference);
    final owner = _client?.userID;
    if (uri == null ||
        owner == null ||
        !uri.isScheme('mxc') ||
        uri.pathSegments.length != 1 ||
        !RegExp(r'^[A-Za-z0-9_-]{1,255}$').hasMatch(uri.pathSegments.single) ||
        uri.authority != owner.substring(owner.indexOf(':') + 1)) {
      return;
    }
    final kind = event.content['net.send.animated'] == true
        ? 'gifs'
        : switch (event.attachmentMimetype) {
            'image/gif' => 'gifs',
            final mime when mime.startsWith('image/') => 'images',
            final mime when mime.startsWith('video/') => 'videos',
            final mime when mime.startsWith('audio/') => 'audio',
            _ => 'other',
          };
    final source = Uri.tryParse(
      event.content['net.deltiecord.gif_source'] as String? ?? '',
    );
    try {
      final labels = await _openUploadLabels();
      await labels?.add(
        uri.pathSegments.single,
        kind,
        source?.host == 'static.klipy.com' || source?.host == 'klipy.com'
            ? 'klipy'
            : 'upload',
      );
      // Thumbnails are protected assets, not a second prunable photo.
      final info = event.content.tryGetMap<String, Object?>('info');
      final thumbnail = Uri.tryParse(
        (info?.tryGetMap<String, Object?>('thumbnail_file')?['url'] ??
                    info?['thumbnail_url'])
                as String? ??
            '',
      );
      if (thumbnail?.isScheme('mxc') == true &&
          thumbnail!.authority == uri.authority &&
          thumbnail.pathSegments.length == 1) {
        await labels?.add(thumbnail.pathSegments.single, 'images', 'asset');
      }
      unawaited(labels?.flush());
    } catch (_) {
      _labelledEvents.remove(event.eventId);
    }
  }

  @override
  Future<Map<String, dynamic>> serverStorage(
    String action, [
    Map<String, Object?>? body,
  ]) async {
    final client = _matrix;
    final homeserver = client.homeserver;
    final token = client.accessToken;
    if (homeserver == null || token == null) {
      throw StateError('Sign in to manage server storage.');
    }
    if (action == 'usage' && _preferences.shareUploadCategories) {
      await (await _openUploadLabels())?.flush(force: true);
    }
    if (!identical(client, _client)) throw StateError('Session changed.');
    return ServerStorageClient(
      client.httpClient,
      homeserver,
      token,
    ).call(action, body);
  }

  Future<void> _recordAssetUpload(Uri uri, Uint8List bytes) async {
    if (!_preferences.shareUploadCategories) return;
    try {
      if (uri.pathSegments.length != 1) return;
      final labels = await _openUploadLabels();
      await labels?.add(
        uri.pathSegments.single,
        hasAnimatedImageHeader(bytes) ? 'gifs' : 'images',
        'asset',
      );
      unawaited(labels?.flush());
    } catch (_) {
      // Upload success must not turn into a duplicate send on a label failure.
    }
  }

  Client? _client;
  Timeline? _timeline;
  MatrixVoiceController? _voice;
  Timer? _typingStopTimer;
  late final _backendUpdates = CoalescedCallback(() {
    countUiDiagnostic('backend.notify');
    notifyListeners();
  }, enabled: kIsWeb);
  int _inboxRequestRevision = 0;
  @override
  int get inboxRequestRevision => _inboxRequestRevision;
  @override
  int get pendingInviteCount =>
      _client?.rooms
          .where((room) => room.membership == Membership.invite)
          .length ??
      0;
  late final _preferenceWriter = SettingsWriter<AppPreferences>(
    write: _writePreferences,
    changed: _notifyBackendListeners,
  );
  final _sessionScope = SessionScope();
  AppPreferences? get _pendingPreferences => _preferenceWriter.pending;
  final _settingsEchoGuard = SettingsEchoGuard();
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
  DateTime? _lastResumeTimelineRefresh;
  final Map<String, Uint8List> _avatarBytes = {};
  final Map<String, Uri?> _avatarUris = {};
  final Map<String, Uint8List> _notificationAvatarBytes = {};
  final Map<String, Uint8List> _senderAvatarBytes = {};
  final Map<String, Uint8List> _spaceProfileAvatarBytes = {};
  final Map<String, Uint8List> _spaceProfileBannerBytes = {};
  final Map<String, Uint8List> _spaceProfileVoiceBackgroundBytes = {};
  final Map<String, Uri?> _senderAvatarUris = {};
  final Map<String, Uri> _memberAvatarUris = {};
  final Set<String> _memberAvatarLoads = {};
  int _memberAvatarGeneration = 0;
  final Map<String, DateTime> _memberAvatarRetryAfter = {};
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
  final _profileWatchers =
      <String, Map<Object, ({bool Function() visible, bool expanded})>>{};
  final _profileCheckedThisSession = <String>{};
  final _profileLastChecked = <String, DateTime>{};
  @override
  Future<void> refreshVisibleAvatar(String id) async {
    final client = _client;
    if (client == null || !_applicationForeground) return;
    final room =
        client.getRoomById(id) ??
        _homeRooms.where((r) => r.directChatMatrixID == id).firstOrNull;
    if (room == null) return;
    try {
      await room.postLoad();
      if (!room.isSpace && !_roomHeroUsersLoaded.contains(room.id)) {
        await room.loadHeroUsers();
        _roomHeroUsersLoaded.add(room.id);
      }
      if (identical(client, _client) && await _refreshAvatar(room)) {
        _notifyBackendListeners();
      }
    } catch (_) {
      // The initial placeholder remains usable while a media fetch is unavailable.
    }
  }

  DateTime? _profileBatchRetryAfter;
  @override
  void Function() watchProfile(
    String id, {
    required bool Function() isVisible,
    bool expanded = false,
  }) {
    final key = Object();
    (_profileWatchers[id] ??= {})[key] = (
      visible: isVisible,
      expanded: expanded,
    );
    return () {
      final entries = _profileWatchers[id];
      entries?.remove(key);
      if (entries?.isEmpty == true) _profileWatchers.remove(id);
    };
  }

  final LinkedHashSet<String> _avatarValidatedEventIds = LinkedHashSet();
  final Set<String> _outboundSessionsReset = {};
  final Set<String> _roomHeroUsersLoaded = {};
  bool _refreshingRoomMetadata = false;
  bool _roomMetadataRefreshRequested = false;
  final Set<String> _roomsMarkingRead = {};
  final Map<String, String> _lastMarkedReadEventIds = {};
  bool _applicationForeground = true;
  bool _desktopIdle = true;
  bool _desktopPresencePublishing = false;
  Timer? _desktopActivityLeaseTimer;
  bool _conversationVisible = false;
  bool _conversationAtPresent = false;
  final Map<String, String?> _firstUnreadEventIds = {};
  final Map<String, String> _lastNotificationEventIds = {};
  final Map<String, DateTime> _lastForegroundAlertAt = {};
  final Map<String, RoomPresentation> _roomPresentationOverrides = {};
  final Map<String, Map<String, dynamic>> _spaceChannelLayoutOverrides = {};
  final Map<String, String> _spaceChannelLayoutEventIds = {};
  final Map<String, List<String>> _spaceRoomOrderOverrides = {};
  final Map<String, Set<String>> _collapsedChannelCategories = {};
  final LinkedHashMap<String, List<ChatMessage>> _roomMessageCache =
      LinkedHashMap();
  final Map<String, String> _offlineSendRooms = {};
  String? _historySearchRoom, _historySearchQuery, _historySearchCursor;
  bool _historySearchComplete = false;
  bool _historySearchOffline = false;
  int _historySearchGeneration = 0;
  final Map<String, ChatMessage> _historySearchMessages = {};
  HistoryIndex? _historyIndex;
  @override
  Future<List<AttachmentDraft>> prepareAttachmentsForSend(
    List<AttachmentDraft> drafts, {
    void Function(int index, String status, double? progress)? onProgress,
  }) async {
    final prepared = await super.prepareAttachmentsForSend(
      drafts,
      onProgress: onProgress,
    );
    // Check the whole batch before uploading its first item.
    for (final item in prepared) {
      await _validateUploadSize(item.bytes.length);
    }
    return prepared;
  }

  HistoryDownload? _historyDownload;
  HistoryGapRecovery? _historyGaps;
  Future<HistoryGapRecovery?>? _openingGaps;
  Timer? _historyGapTimer;
  bool _historyGapTicking = false;
  bool _historyDisposed = false;
  int _historyConfigurationGeneration = 0;
  Future<void> _historySyncQueue = Future.value();
  Future<HistoryDownload?>? _openingDownload;
  @override
  List<HistoryDownloadRoom> get historyDownloadRooms => _joinedRooms
      .where((r) => !r.isSpace)
      .map(
        (r) => HistoryDownloadRoom(
          r.id,
          r.getLocalizedDisplayname(),
          kind: _historyRoomKind(r),
        ),
      )
      .toList();

  HistoryRoomKind _historyRoomKind(Room room) {
    if (_spaceForRoom(room) != null) return HistoryRoomKind.server;
    final memberCount = max(
      (room.summary.mJoinedMemberCount ?? 0) +
          (room.summary.mInvitedMemberCount ?? 0),
      room
          .getParticipants()
          .where(
            (p) =>
                p.membership == Membership.join ||
                p.membership == Membership.invite,
          )
          .length,
    );
    return room.isDirectChat && memberCount <= 2
        ? HistoryRoomKind.dm
        : HistoryRoomKind.group;
  }

  @override
  Future<void> configureHistoryScope(HistoryScope scope) async {
    _historyConfigurationGeneration++;
    final index = await openHistoryIndex();
    if (index == null || _client == null || status != SessionStatus.signedIn) {
      throw StateError('Sign in before changing the search scope.');
    }
    await _historyDownload?.reset();
    await _historyGaps?.reset();
    await index.setScope(
      scope,
      historyDownloadRooms
          .where((r) => scope.includes(r.kind))
          .map((r) => r.id)
          .toSet(),
    );
    _resetIndexedSearch();
    _indexFingerprints.clear();
    _mediaHistory.clear();
    _catalogGeneration++;
    _mediaCursor.clear();
    _mediaEnded.clear();
    _mediaIndexOffset.clear();
    if (_timeline case final timeline?) await _indexEvents(timeline.events);
  }

  @override
  Future<HistoryDownload?> openHistoryDownload() {
    if (_historyDownload != null) return Future.value(_historyDownload);
    return _openingDownload ??= _openHistoryDownload().then((value) {
      if (value == null) _openingDownload = null;
      return value;
    });
  }

  Future<HistoryDownload?> _openHistoryDownload() async {
    final client = _client;
    final index = await openHistoryIndex();
    if (client == null || index == null || !identical(client, _client)) {
      return null;
    }
    late final HistoryDownload download;
    final attemptedBackup = <String>{};
    download = HistoryDownload(
      fetch: (room, cursor) => _downloadIndexPage(
        client,
        room,
        cursor,
        download.guardForCurrentRun(),
        attemptedBackup,
      ),
      append: index.appendArchive,
      retryEvent: (event, active) async {
        if (!active()) throw StateError('Retry paused.');
        final raw = await client
            .getOneRoomEvent(event.roomId, event.eventId)
            .timeout(const Duration(seconds: 15));
        if (!active()) throw StateError('Retry paused.');
        return _downloadIndexPage(
          client,
          event.roomId,
          null,
          active,
          attemptedBackup,
          suppliedEvents: [raw],
        );
      },
      load: index.loadDownloadState,
      save: index.saveDownloadState,
      onRun: attemptedBackup.clear,
      canRun: () =>
          identical(client, _client) &&
          index.enabled &&
          (!(kIsWeb || Platform.isAndroid || Platform.isIOS) ||
              _applicationForeground),
    );
    await download.open();
    if (!identical(client, _client) || !identical(index, _historyIndex)) {
      download.dispose();
      return null;
    }
    return _historyDownload = download;
  }

  Future<HistoryIndex?>? _openingIndex;
  DateTime? _indexRetryAfter;
  String? _indexError;
  @override
  String? get historyIndexError => _indexError;
  @override
  Future<HistoryIndex?> retryHistoryIndex() {
    _indexRetryAfter = null;
    return openHistoryIndex();
  }

  int _indexSearchOffset = 0;
  bool _indexSearchDone = false;
  StreamSubscription<Event>? _indexEventSubscription;
  final _mediaHistory = <String, Map<String, ChatMessage>>{};
  int _catalogGeneration = 0;
  final _mediaCursor = <String, String?>{};
  final _mediaEnded = <String>{};
  final _mediaLoading = <String, Future<List<ChatMessage>>>{};
  final _mediaIndexOffset = <String, int>{};
  final _indexFingerprints = <String, int>{};
  final _indexedEventRooms = <String, String>{};
  @override
  HistoryIndex? get historyIndex => _historyIndex;
  @override
  Future<HistoryIndex?> openHistoryIndex() {
    if (_historyIndex != null) return Future.value(_historyIndex);
    if (_client?.userID == null) return Future.value();
    if (_indexRetryAfter?.isAfter(DateTime.now()) == true) {
      return Future.value();
    }
    return _openingIndex ??= _openHistoryIndex().then((value) {
      if (value == null) _openingIndex = null;
      return value;
    });
  }

  @override
  Future<void> configureHistoryIndex(bool enabled, {int? limitMiB}) async {
    _historyConfigurationGeneration++;
    _historyDownload?.pause(reason: 'Paused while the cache settings change.');
    if (!enabled) await _historyDownload?.reset();
    if (!enabled) await _historyGaps?.reset();
    final index = await openHistoryIndex();
    if (index == null) {
      throw StateError('Local search storage could not be opened.');
    }
    await index.configure(text: enabled, limit: limitMiB);
    _historyGaps?.capacityChanged();
    _historyDownload?.clearCatchupStorageFull();
    if (enabled) unawaited(_openHistoryGaps().catchError((Object _) => null));
    if (!enabled) _resetIndexedSearch();
    _indexFingerprints.clear();
    if (_timeline case final timeline?) await _indexEvents(timeline.events);
  }

  @override
  Future<void> clearHistoryIndex() async {
    _historyConfigurationGeneration++;
    await _historyDownload?.reset();
    await _historyGaps?.reset();
    await _historyIndex?.clear();
    _resetIndexedSearch();
    _indexFingerprints.clear();
    _indexSearchOffset = 0;
    _indexSearchDone = false;
    _mediaIndexOffset.clear();
  }

  void _resetIndexedSearch() {
    _historySearchGeneration++;
    _historySearchMessages.clear();
    _historySearchRoom = _historySearchQuery = _historySearchCursor = null;
    _historySearchComplete = _historySearchOffline = false;
    _indexSearchOffset = 0;
    _indexSearchDone = false;
  }

  Future<HistoryIndex?> _openHistoryIndex() async {
    final client = _client;
    if (client?.userID == null) return null;
    final index = _historyIndexFactory(client!.userID!);
    try {
      await index.open();
      if (!identical(client, _client)) {
        await index.close();
        return null;
      }
      _historyIndex = index;
      if (index.enabled) {
        scheduleMicrotask(
          () => unawaited(_openHistoryGaps().catchError((Object _) => null)),
        );
      }
      _indexRetryAfter = null;
      _indexError = null;
      index.addListener(_indexWarningChanged);
      await _indexEventSubscription?.cancel();
      _indexEventSubscription = client.onTimelineEvent.stream.listen((event) {
        unawaited(_indexEvents([event]).catchError((Object _) {}));
      });
      _notifyBackendListeners();
      return index;
    } catch (error) {
      _indexRetryAfter = DateTime.now().add(const Duration(minutes: 1));
      _indexError =
          'Search storage failed at ${index.openStage} (${index.failureCode(error)}). '
          'Existing data has not been reset.';
      await index.close();
      return null;
    }
  }

  bool _indexWarningPending = false;
  void _indexWarningChanged() {
    final pending = _historyIndex?.warningPending == true;
    if (pending != _indexWarningPending) {
      _indexWarningPending = pending;
      _notifyBackendListeners();
    }
  }

  @override
  List<ChatMessage> mediaMessagesForRoom(String roomId) {
    final result = <String, ChatMessage>{
      ...?_mediaHistory[roomId],
      if (roomId == _selectedRoomId)
        for (final message in messages)
          if (message.attachment?.kind == AttachmentKind.image ||
              message.attachment?.kind == AttachmentKind.video)
            message.id: message,
    };
    return result.values.where((m) => !m.redacted).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  bool canLoadMoreMedia(String roomId) => !_mediaEnded.contains(roomId);
  @override
  Future<List<ChatMessage>> loadMoreMedia(String roomId) =>
      _loadCatalogOnce(roomId, 'media');
  @override
  List<ChatMessage> catalogMessagesForRoom(String roomId, String kind) {
    if (kind == 'media') return mediaMessagesForRoom(roomId);
    final key = '$roomId|$kind';
    final rows = <String, ChatMessage>{
      ...?_mediaHistory[key],
      if (roomId == _selectedRoomId)
        for (final message in messages)
          if (catalogMatches(message, kind)) message.id: message,
    };
    return rows.values.where((m) => catalogMatches(m, kind)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  bool canLoadMoreCatalog(String roomId, String kind) =>
      !_mediaEnded.contains(kind == 'media' ? roomId : '$roomId|$kind');
  @override
  Future<List<ChatMessage>> loadMoreCatalog(String roomId, String kind) {
    if (!{'media', 'document', 'link'}.contains(kind)) {
      throw ArgumentError('Unknown catalog');
    }
    return _loadCatalogOnce(roomId, kind);
  }

  Future<List<ChatMessage>> _loadCatalogOnce(String roomId, String kind) {
    final key = kind == 'media' ? roomId : '$roomId|$kind';
    final pending = _mediaLoading[key];
    if (pending != null) return pending;
    late final Future<List<ChatMessage>> request;
    request = _loadMediaPage(roomId, kind: kind).whenComplete(() {
      if (identical(_mediaLoading[key], request)) _mediaLoading.remove(key);
    });
    _mediaLoading[key] = request;
    return request;
  }

  void _removeCatalogEvent(String roomId, String id) {
    for (final key in [roomId, '$roomId|document', '$roomId|link']) {
      _mediaHistory[key]?.remove(id);
    }
  }

  @override
  bool get canLoadMoreSearchResults =>
      _historySearchRoom == _selectedRoomId &&
      (!_indexSearchDone || !_historySearchComplete);
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
  List<SpaceSummary> get spaces {
    final rooms = _joinedRooms.where((room) => room.isSpace).toList();
    final saved = _personal?.spaceOrder ?? const <String>[];
    final ids = [
      ...saved,
      ...rooms.map((r) => r.id).where((id) => !saved.contains(id)),
    ];
    rooms.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));
    return rooms
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
  }

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
    // SeND also walks its persisted-event cursor before falling back to
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
  RtcConnectivity get rtcConnectivity =>
      _voice?.connectivity ?? const RtcConnectivity();
  @override
  String? get activeVoiceRoomId => _voice?.activeRoomId;
  @override
  ({String roomId, String callerName, String callerId})? get incomingCall =>
      _voice?.incomingCall;
  @override
  void dismissIncomingCall() => _voice?.dismissIncomingCall();
  @override
  bool canChangeRoomState(String roomId, String eventType) =>
      _matrix.getRoomById(roomId)?.canChangeStateEvent(eventType) ?? false;
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
      _rolesForRoom(room).roles.map(
        (role) => MentionSuggestion(
          matrixId: '@${role.name}',
          displayName: '${role.name} (role)',
          isRole: true,
        ),
      ),
    );
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
    unawaited(_hydrateMemberAvatars(room));
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
            // ignore: deprecated_member_use
            statusMessage: _matrix.presences[user.id]?.statusMsg,
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
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    return messages
        .where(
          (message) => matchesMessageSearch(
            body: message.body,
            formattedBody: message.formattedBody,
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
    final joined = visible
        .where(
          (r) =>
              selectedSpaceId != null || !(_personal?.archived(r.id) ?? false),
        )
        .map(_roomSummary)
        .toList(growable: false);
    if (selectedSpaceId == null) {
      final ranks = {for (var i = 0; i < joined.length; i++) joined[i].id: i};
      joined.sort((a, b) {
        final pin = (_personal?.pinned(b.id) == true ? 1 : 0).compareTo(
          _personal?.pinned(a.id) == true ? 1 : 0,
        );
        return pin != 0 ? pin : ranks[a.id]!.compareTo(ranks[b.id]!);
      });
    }
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
  int get serverPingCount {
    final serverRooms = _allSpaceChildIds;
    return _joinedRooms
        .where(
          (room) =>
              !room.isSpace &&
              (serverRooms.contains(room.id) || !room.isDirectChat),
        )
        .fold(0, (sum, room) => sum + room.highlightCount);
  }

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

  PersonalData? _personal;
  Future<void>? _openingPersonal;
  @override
  PersonalData? get personalData => _personal;
  @override
  List<RoomSummary> get archivedRooms => _homeRooms
      .where((r) => _personal?.archived(r.id) == true)
      .map(_roomSummary)
      .toList();
  Future<void> _startPersonalData() => _openingPersonal ??= _openPersonalData();
  Future<void> _openPersonalData() async {
    final client = _client;
    if (client?.userID == null) {
      _openingPersonal = null;
      return;
    }
    if (_personal?.account == client!.userID) return;
    await _personal?.close();
    final personal = PersonalData(
      account: client.userID!,
      write: (type, data) => client.setAccountData(client.userID!, type, data),
    );
    try {
      await personal.open({
        for (final e in client.accountData.entries) e.key: e.value.content,
      });
      if (!identical(client, _client)) {
        await personal.close();
        return;
      }
      _personal = personal;
      FavouriteReactionsStore.instance.bind(personal);
      GifService.bind(personal);
      personal.addListener(_notifyBackendListeners);
      _notifyBackendListeners();
    } catch (_) {
      await personal.close();
      _openingPersonal = null;
    }
  }

  Set<String> get _allSpaceChildIds => _joinedRooms
      .where((room) => room.isSpace)
      .expand((space) => space.spaceChildren)
      .map((child) => child.roomId)
      .whereType<String>()
      .toSet();

  List<Room> get _homeRooms {
    final serverRooms = _allSpaceChildIds;
    // m.direct is a user annotation and can contain stale channel entries.
    // Joined server membership takes precedence without rewriting account data.
    return _joinedRooms
        .where((room) => !room.isSpace && !serverRooms.contains(room.id))
        .toList(growable: false);
  }

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
  bool get reconcilesOutgoingTransactions => true;

  @override
  List<ChatMessage> get bookmarkedMessages => _roomMessageCache.values
      .expand((messages) => messages)
      .where((message) => _bookmarkedEventIds.contains(message.id))
      .toList(growable: false);

  @override
  String? roomIdForMessage(String eventId) {
    if (_indexedEventRooms[eventId] case final room?) return room;
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
    countUiDiagnostic('backend.request', source: () => StackTrace.current);
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
      _applicationForeground &&
      _conversationVisible &&
      _conversationAtPresent &&
      !_manualUnreadHolds.contains(_selectedRoomId);

  final _manualUnreadHolds = <String>{};
  @override
  Future<void> markMessageUnread(String eventId) async {
    final room = roomIdForMessage(eventId) ?? _selectedRoomId;
    if (room == null) return;
    _manualUnreadHolds.add(room);
    try {
      await _markRoomUnread(room, true);
      _firstUnreadEventIds[room] = eventId;
      _notifyBackendListeners();
    } catch (_) {
      _manualUnreadHolds.remove(room);
      rethrow;
    }
  }

  @override
  void setApplicationForeground(bool foreground) {
    if (_applicationForeground == foreground) {
      if (foreground) _dismissVisibleRoomNotification();
      if (_mayAdvanceReadMarker) unawaited(_markSelectedRoomRead());
      return;
    }
    final previousPresence = _effectiveClientPresence;
    _applicationForeground = foreground;
    if (foreground) unawaited(_tickHistoryGaps());
    if (!foreground && (kIsWeb || Platform.isAndroid || Platform.isIOS)) {
      _historyDownload?.pause(
        reason: 'Paused while SeND is in the background.',
      );
    }
    _configureClientPresence();
    if (previousPresence != _effectiveClientPresence) {
      unawaited(_refreshDesktopPresence());
    }
    _activities?.visibilityChanged();
    if (foreground) _lastForegroundAlertAt.clear();
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
    if (kIsWeb && _client?.isLogged() == true) {
      unawaited(reconcileBrowserPush(_matrix).catchError((Object _) {}));
    }
    if (_applicationForeground) unawaited(_refreshTimelineAfterResume());
    _notifyBackendListeners();
  }

  @override
  void setDesktopIdle(bool idle) => _setDesktopIdle(idle);

  @override
  void setConversationVisible(bool visible) {
    final changed = _conversationVisible != visible;
    _conversationVisible = visible;
    if (changed && _applicationForeground && _client?.isLogged() == true) {
      unawaited(
        Future<void>.delayed(
          Duration.zero,
        ).then((_) => _refreshActiveProfileCache()).catchError((Object _) {}),
      );
    }
    _dismissVisibleRoomNotification();
    if (_mayAdvanceReadMarker) unawaited(_markSelectedRoomRead());
  }

  void _dismissVisibleRoomNotification() {
    final roomId = _selectedRoomId;
    // Dismissal is about what is visible, not whether history is scrolled to
    // the newest event. Read receipts retain their stricter at-present guard.
    if (_applicationForeground && _conversationVisible && roomId != null) {
      _lastForegroundAlertAt.remove(roomId);
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
          await room.setReadMarker(
            eventId,
            mRead: eventId,
            public: _preferences.sendReadReceipts,
          );
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
  bool canMarkRoomDirect(String roomId) {
    final room = _matrix.getRoomById(roomId);
    return room != null && !room.isSpace && _spaceForRoom(room) == null;
  }

  @override
  bool isRoomDirect(String roomId) =>
      canMarkRoomDirect(roomId) && _matrix.getRoomById(roomId)!.isDirectChat;

  @override
  Future<void> setRoomDirect(String roomId, bool direct) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null || room.isSpace) {
      throw StateError('Choose a joined conversation.');
    }
    if (direct && !canMarkRoomDirect(roomId)) {
      throw StateError('Server channels cannot be marked as DMs.');
    }
    final members = direct ? await room.requestParticipants() : <User>[];
    final mapping = <String, List<String>>{
      for (final entry in _matrix.directChats.entries)
        entry.key: entry.value.where((id) => id != roomId).toList(),
    }..removeWhere((_, ids) => ids.isEmpty);
    if (direct) {
      final peers = members
          .where(
            (m) =>
                m.id != _matrix.userID &&
                (m.membership == Membership.join ||
                    m.membership == Membership.invite),
          )
          .toList();
      final ids = peers.isEmpty ? [_matrix.userID!] : peers.map((m) => m.id);
      for (final id in ids) {
        mapping.putIfAbsent(id, () => []).add(roomId);
      }
    }
    // Account annotation only: never modify membership, access or encryption.
    await _matrix.setAccountData(_matrix.userID!, 'm.direct', mapping);
    _notifyBackendListeners();
  }

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
  void selectSpace(String? spaceId) {
    if (spaceId != null && archiveOpen) setArchiveOpen(false);
    _selectSpace(spaceId);
  }

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
  Future<void> createSpace({
    required String name,
    String topic = '',
    bool encrypted = true,
  }) => _createSpace(name: name, topic: topic, encrypted: encrypted);
  @override
  bool get defaultChannelEncryption =>
      _matrix
          .getRoomById(_selectedSpaceId ?? '')
          ?.getState('net.send.channel_encryption')
          ?.content['enabled'] !=
      false;
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
  bool canInviteToRoom(String roomId) =>
      _client?.getRoomById(roomId)?.canInvite ?? false;
  @override
  Future<void> inviteMember(String userId, {String? reason, String? roomId}) =>
      _inviteMember(userId, reason: reason, roomId: roomId);
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
  Future<Uint8List?> getProfileImage(
    String userId, {
    required bool banner,
  }) async {
    final spaceId = selectedRoomSpaceId;
    final member = spaceId == null
        ? null
        : _matrix
              .getRoomById(spaceId)
              ?.getState(EventTypes.RoomMember, userId)
              ?.content;
    final override = member == null
        ? null
        : member[banner ? _profileBannerField : 'avatar_url'] ??
              (banner ? member['banner_url'] : null);
    final overrideUri = override is String ? Uri.tryParse(override) : null;
    if (overrideUri?.isScheme('mxc') == true) {
      return (await _matrix.getContent(
        overrideUri!.host,
        overrideUri.pathSegments.join('/'),
      )).data;
    }
    final profile = await _matrix.getUserProfile(userId);
    final uri = banner
        ? Uri.tryParse(
            profile.additionalProperties[_profileBannerField] as String? ?? '',
          )
        : profile.avatarUrl;
    if (uri == null || !uri.isScheme('mxc')) return null;
    return (await _matrix.getContent(
      uri.host,
      uri.pathSegments.join('/'),
    )).data;
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
    _sessionScope.dispose();
    _threadHistory?.dispose();
    _historyDisposed = true;
    _historyDownload?.dispose();
    _historyGapTimer?.cancel();
    _historyGaps?.dispose();
    _personal?.removeListener(_notifyBackendListeners);
    _historyIndex?.removeListener(_indexWarningChanged);
    unawaited(_indexEventSubscription?.cancel());
    unawaited(_historyIndex?.close());
    FavouriteReactionsStore.instance.bind(null);
    GifService.bind(null);
    unawaited(_personal?.close());
    if (kIsWeb) browser.configureBrowserPresence(null);
    _memberAvatarGeneration++;
    if (kIsWeb) BrowserPushPreviews.stop();
    unawaited(_stopActivities());
    _browserAuthenticationCanceled = true;
    final authBrowser = _activeAuthBrowser;
    if (authBrowser != null) unawaited(authBrowser.close());
    for (final session in _threadSessions.toList()) {
      session.dispose();
    }
    _backendUpdates.dispose();
    _typingStopTimer?.cancel();
    _preferenceWriter.dispose();
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
