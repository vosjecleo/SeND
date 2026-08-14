import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/chat_notifications.dart';
import 'matrix_client_factory.dart';
import 'deltiecord_webrtc_delegate.dart';
import 'media_range_proxy.dart';

class MatrixBackend extends ChatBackend {
  static const _settingsAccountDataType = 'net.deltiecord.settings';
  static const _roomPresentationEventType = 'net.deltiecord.room.presentation';

  MatrixBackend({ChatNotificationSink? notifications})
    : _notifications = notifications ?? const SilentChatNotificationSink();

  final ChatNotificationSink _notifications;
  Client? _client;
  Timeline? _timeline;
  VoIP? _voip;
  GroupCallSession? _activeVoiceCall;
  StreamSubscription<MatrixRTCCallEvent>? _voiceCallSubscription;
  VoiceConnectionStatus _voiceConnectionStatus =
      VoiceConnectionStatus.disconnected;
  bool _voiceMuted = false;
  String? _voiceError;
  String? _activeSpeakerUserId;
  List<AudioInputSummary> _audioInputs = const [];
  String? _selectedAudioInputId;
  Timer? _typingStopTimer;
  String? _typingRoomId;
  StreamSubscription<Object?>? _syncSubscription;
  StreamSubscription<Object?>? _loginSubscription;
  SessionStatus _status = SessionStatus.starting;
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
  int? _maximumUploadBytes;
  final MediaRangeProxy _mediaRangeProxy = MediaRangeProxy();
  final Map<String, MediaPlaybackSource> _mediaPlaybackSources = {};
  EncryptionSetupState _encryptionSetup = const EncryptionSetupState(
    status: EncryptionSetupStatus.loading,
  );

  Client get _matrix => _client!;

  @override
  SessionStatus get status => _status;
  @override
  String? get error => _error;
  @override
  String? get userId => _client?.userID;
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
  VoiceConnectionStatus get voiceConnectionStatus => _voiceConnectionStatus;
  @override
  String? get activeVoiceRoomId => _activeVoiceCall?.room.id;
  @override
  bool get voiceMuted => _voiceMuted;
  @override
  String? get voiceError => _voiceError;
  @override
  List<AudioInputSummary> get audioInputs => _audioInputs;
  @override
  String? get selectedAudioInputId => _selectedAudioInputId;
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

  List<Room> _roomsForSpace(String spaceId) {
    final space = _client?.getRoomById(spaceId);
    if (space == null || !space.isSpace) return const [];
    final children = space.spaceChildren
        .map((child) => _client?.getRoomById(child.roomId ?? ''))
        .whereType<Room>()
        .where((room) => room.membership == Membership.join && !room.isSpace);
    return children.toList(growable: false);
  }

  @override
  RoomSummary? get selectedRoom {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    return room == null ? null : _roomSummary(room);
  }

  @override
  bool get selectedRoomMuted =>
      _client?.getRoomById(_selectedRoomId ?? '')?.pushRuleState ==
      PushRuleState.dontNotify;

  @override
  List<ChatMessage> get messages {
    final timeline = _timeline;
    if (timeline == null) return const [];
    return timeline.events
        .where((event) => _isVisibleTimelineEvent(event))
        .where((event) => event.relationshipType != RelationshipTypes.edit)
        .map((event) {
          final displayEvent = event.type == EventTypes.Message
              ? event.getDisplayEvent(timeline)
              : event;
          final isMessage =
              displayEvent.type == EventTypes.Message ||
              displayEvent.type == EventTypes.Encrypted;
          final attachment = _attachmentFor(displayEvent);
          final body = event.redacted
              ? 'Message deleted'
              : displayEvent.type == EventTypes.Encrypted
              ? 'Unable to decrypt this message'
              : !isMessage
              ? _systemEventBody(displayEvent)
              : attachment?.caption ??
                    (attachment == null
                        ? displayEvent.calcUnlocalizedBody(
                            hideReply: true,
                            hideEdit: true,
                            plaintextBody: true,
                          )
                        : '');
          return ChatMessage(
            id: event.eventId,
            sender: event.senderFromMemoryOrFallback.calcDisplayname(),
            body: body,
            timestamp: event.originServerTs,
            pending: event.status.isSending,
            failed: event.status.isError,
            transferStatus: switch (event.fileSendingStatus) {
              FileSendingStatus.generatingThumbnail => 'Preparing preview…',
              FileSendingStatus.encrypting => 'Encrypting…',
              FileSendingStatus.uploading => 'Uploading…',
              null => null,
            },
            system: !isMessage,
            own: event.senderId == _matrix.userID,
            canRedact: event.canRedact && !event.redacted,
            edited: displayEvent.eventId != event.eventId,
            redacted: event.redacted,
            reactions: _reactionSummaries(event, timeline),
            attachment: attachment,
            formattedBody:
                displayEvent.isRichMessage &&
                    (attachment == null || attachment.caption != null)
                ? displayEvent.formattedText
                : null,
            reply: _replyPreviews[event.eventId],
            avatarBytes: _senderAvatarBytes[event.senderId],
            linkPreview: _linkPreviews[event.eventId],
          );
        })
        .toList(growable: false);
  }

  bool _isVisibleTimelineEvent(Event event) =>
      event.type == EventTypes.Message ||
      event.type == EventTypes.Encrypted ||
      event.type == EventTypes.RoomMember ||
      event.type == EventTypes.RoomName ||
      event.type == EventTypes.RoomTopic ||
      event.type == EventTypes.RoomAvatar ||
      event.type == EventTypes.Encryption;

  String _systemEventBody(Event event) {
    final actor = event.senderFromMemoryOrFallback.calcDisplayname();
    if (event.type == EventTypes.RoomMember) {
      final user =
          event.stateKeyUser?.calcDisplayname() ?? event.stateKey ?? actor;
      return switch (event.roomMemberChangeType) {
        RoomMemberChangeType.join => '$user joined the room',
        RoomMemberChangeType.acceptInvite => '$user accepted the invitation',
        RoomMemberChangeType.rejectInvite => '$user rejected the invitation',
        RoomMemberChangeType.withdrawInvitation =>
          '$actor withdrew the invitation for $user',
        RoomMemberChangeType.leave => '$user left the room',
        RoomMemberChangeType.kick => '$actor removed $user from the room',
        RoomMemberChangeType.invite => '$actor invited $user',
        RoomMemberChangeType.ban => '$actor banned $user',
        RoomMemberChangeType.unban => '$actor unbanned $user',
        RoomMemberChangeType.knock => '$user requested to join',
        RoomMemberChangeType.avatar => '$user changed their profile picture',
        RoomMemberChangeType.displayname => _displayNameChange(event, user),
        RoomMemberChangeType.other => '$user updated their room profile',
      };
    }
    return switch (event.type) {
      EventTypes.RoomName =>
        '$actor changed the room name to ${event.content.tryGet<String>('name') ?? 'an unnamed room'}',
      EventTypes.RoomTopic =>
        '$actor changed the topic to ${event.content.tryGet<String>('topic') ?? ''}',
      EventTypes.RoomAvatar => '$actor changed the room picture',
      EventTypes.Encryption => '$actor enabled end-to-end encryption',
      _ => '$actor updated the room',
    };
  }

  String _displayNameChange(Event event, String currentName) {
    final previousName = event.prevContent?.tryGet<String>('displayname');
    if (previousName == null || previousName.isEmpty) {
      return '${event.stateKey ?? currentName} is now known as $currentName';
    }
    return '$previousName changed their name to $currentName';
  }

  ChatAttachment? _attachmentFor(Event event) {
    if (!event.hasAttachment) return null;
    final kind = switch (event.messageType) {
      MessageTypes.Image => AttachmentKind.image,
      MessageTypes.Video => AttachmentKind.video,
      MessageTypes.Audio => AttachmentKind.audio,
      _ => AttachmentKind.file,
    };
    final name = event.content.tryGet<String>('filename') ?? event.body;
    final caption =
        event.body.trim().isNotEmpty && event.body.trim() != name.trim()
        ? event.body.trim()
        : null;
    return ChatAttachment(
      kind: kind,
      name: name,
      mimeType: event.attachmentMimetype,
      size: event.infoMap.tryGet<int>('size'),
      encrypted: event.isAttachmentEncrypted,
      spoiler:
          event.content.tryGet<bool>(
                'page.codeberg.everypizza.msc4193.spoiler',
              ) ==
              true ||
          event.content.tryGet<bool>('m.spoiler') == true,
      caption: caption,
      hasThumbnail: event.hasThumbnail,
      animated: event.attachmentMimetype == 'image/gif',
      width: event.infoMap.tryGet<int>('w'),
      height: event.infoMap.tryGet<int>('h'),
    );
  }

  List<ReactionSummary> _reactionSummaries(Event event, Timeline timeline) {
    final reactions = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final counts = <String, int>{};
    final mine = <String>{};
    for (final reaction in reactions.where((reaction) => !reaction.redacted)) {
      final key = reaction.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key == null || key.isEmpty) continue;
      counts.update(key, (count) => count + 1, ifAbsent: () => 1);
      if (reaction.senderId == _matrix.userID) mine.add(key);
    }
    final summaries = counts.entries
        .map(
          (entry) => ReactionSummary(
            key: entry.key,
            count: entry.value,
            reactedByMe: mine.contains(entry.key),
          ),
        )
        .toList(growable: false);
    summaries.sort((a, b) => a.key.compareTo(b.key));
    return summaries;
  }

  @override
  Future<void> initialize() async {
    try {
      await _syncSubscription?.cancel();
      await _loginSubscription?.cancel();
      _client?.dispose();
      _client = await createMatrixClient();
      _syncSubscription = _matrix.onSync.stream.listen((_) {
        _loadSettings();
        notifyListeners();
        unawaited(_refreshRoomMetadata());
        unawaited(_notifyNewMessages());
      });
      _loginSubscription = _matrix.onLoginStateChanged.stream.listen((_) {
        _status = _matrix.isLogged()
            ? SessionStatus.signedIn
            : SessionStatus.signedOut;
        notifyListeners();
      });
      await _matrix.init();
      _initializeVoip();
      _loadSettings();
      await _notifications.initialize();
      _status = _matrix.isLogged()
          ? SessionStatus.signedIn
          : SessionStatus.signedOut;
      _error = null;
      if (_matrix.isLogged()) {
        unawaited(refreshEncryptionSetup());
        unawaited(_refreshRoomMetadata());
        unawaited(_refreshMediaConfig());
      }
    } catch (exception) {
      _status = SessionStatus.failed;
      _error = _friendlyError(exception);
    }
    notifyListeners();
  }

  @override
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    _status = SessionStatus.signingIn;
    _error = null;
    notifyListeners();
    try {
      await _matrix.checkHomeserver(homeserver);
      await _matrix.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
        initialDeviceDisplayName: 'Deltiecord Desktop',
      );
      _initializeVoip();
      _status = SessionStatus.signedIn;
      unawaited(_refreshMediaConfig());
      await refreshEncryptionSetup();
    } catch (exception) {
      _status = SessionStatus.signedOut;
      _error = _friendlyError(exception);
    }
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    _error = null;
    try {
      await leaveVoiceRoom();
      await _closeTimeline();
      await _matrix.logout();
      _selectedRoomId = null;
      _selectedSpaceId = null;
      _loadedBackupRoomIds.clear();
      _avatarBytes.clear();
      _avatarUris.clear();
      _senderAvatarBytes.clear();
      _senderAvatarUris.clear();
      _decryptedPreviews.clear();
      _replyPreviews.clear();
      _linkPreviews.clear();
      _outboundSessionsReset.clear();
      _roomsMarkingRead.clear();
      _lastMarkedReadEventIds.clear();
      _firstUnreadEventIds.clear();
      _lastNotificationEventIds.clear();
      _roomPresentationOverrides.clear();
      _notificationsPrimed = false;
      _maximumUploadBytes = null;
      _mediaPlaybackSources.clear();
      _mediaRangeProxy.clear();
      _encryptionSetup = const EncryptionSetupState(
        status: EncryptionSetupStatus.loading,
      );
      _status = SessionStatus.signedOut;
    } catch (exception) {
      _error = _friendlyError(exception);
    }
    notifyListeners();
  }

  void _initializeVoip() {
    if (!_matrix.isLogged() || _voip != null) return;
    _voip = VoIP(
      _matrix,
      DeltiecordWebRtcDelegate(
        isCallActive: () =>
            _voiceConnectionStatus == VoiceConnectionStatus.connecting ||
            _voiceConnectionStatus == VoiceConnectionStatus.connected,
      ),
    );
    unawaited(refreshAudioInputs());
  }

  @override
  Future<void> refreshAudioInputs() async {
    try {
      final devices = await flutter_webrtc.navigator.mediaDevices
          .enumerateDevices();
      _audioInputs = devices
          .where((device) => device.kind == 'audioinput')
          .map(
            (device) => AudioInputSummary(
              id: device.deviceId,
              label: device.label.isEmpty ? 'Microphone' : device.label,
            ),
          )
          .toList(growable: false);
      if (_selectedAudioInputId != null &&
          !_audioInputs.any((input) => input.id == _selectedAudioInputId)) {
        _selectedAudioInputId = null;
      }
    } catch (_) {
      _audioInputs = const [];
    }
    notifyListeners();
  }

  @override
  Future<void> selectAudioInput(String? deviceId) async {
    if (_selectedAudioInputId == deviceId) return;
    final reconnectRoomId = activeVoiceRoomId;
    _selectedAudioInputId = deviceId;
    notifyListeners();
    if (reconnectRoomId != null) {
      await leaveVoiceRoom();
      await joinVoiceRoom(reconnectRoomId);
    }
  }

  @override
  Future<void> joinVoiceRoom(String roomId) async {
    if (activeVoiceRoomId == roomId &&
        _voiceConnectionStatus == VoiceConnectionStatus.connected) {
      return;
    }
    if (_activeVoiceCall != null) await leaveVoiceRoom();
    final room = _matrix.getRoomById(roomId);
    if (room == null) return;
    _initializeVoip();
    final voip = _voip;
    if (voip == null) return;
    _voiceConnectionStatus = VoiceConnectionStatus.connecting;
    _voiceError = null;
    notifyListeners();
    try {
      final call = await voip.fetchOrCreateGroupCall(
        room.id,
        room,
        MeshBackend(),
        'm.call',
        'm.room',
      );
      _activeVoiceCall = call;
      await _voiceCallSubscription?.cancel();
      _voiceCallSubscription = call.matrixRTCEventStream.stream.listen(
        _handleVoiceCallEvent,
      );
      final audioConstraints = <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        if (_selectedAudioInputId != null)
          'deviceId': {'exact': _selectedAudioInputId},
      };
      final stream = await flutter_webrtc.navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints,
        'video': false,
      });
      final wrappedStream = WrappedMediaStream(
        stream: stream,
        participant: call.localParticipant!,
        room: room,
        client: _matrix,
        purpose: SDPStreamMetadataPurpose.Usermedia,
        audioMuted: false,
        videoMuted: true,
        isGroupCall: true,
        voip: voip,
      );
      await call.enter(stream: wrappedStream);
      _voiceConnectionStatus = VoiceConnectionStatus.connected;
    } catch (exception) {
      _voiceConnectionStatus = VoiceConnectionStatus.error;
      _voiceError = _friendlyError(exception);
      _activeVoiceCall = null;
    }
    notifyListeners();
  }

  void _handleVoiceCallEvent(MatrixRTCCallEvent event) {
    switch (event) {
      case GroupCallStateChanged(:final state):
        _voiceConnectionStatus = switch (state) {
          GroupCallState.entered => VoiceConnectionStatus.connected,
          GroupCallState.entering ||
          GroupCallState.initializingLocalCallFeed ||
          GroupCallState.localCallFeedInitialized =>
            VoiceConnectionStatus.connecting,
          GroupCallState.leaving => VoiceConnectionStatus.disconnecting,
          GroupCallState.ended || GroupCallState.localCallFeedUninitialized =>
            VoiceConnectionStatus.disconnected,
        };
      case GroupCallStateError(:final msg):
        _voiceConnectionStatus = VoiceConnectionStatus.error;
        _voiceError = msg;
      case GroupCallLocalMutedChanged(:final muted, :final kind):
        if (kind == MediaInputKind.audioinput) _voiceMuted = muted;
      case GroupCallActiveSpeakerChanged(:final participant):
        _activeSpeakerUserId = participant.userId;
      case ParticipantsChangeEvent():
        break;
      default:
        break;
    }
    notifyListeners();
  }

  @override
  Future<void> setVoiceMuted(bool muted) async {
    final call = _activeVoiceCall;
    if (call == null) return;
    await call.backend.setDeviceMuted(call, muted, MediaInputKind.audioinput);
    _voiceMuted = muted;
    notifyListeners();
  }

  @override
  Future<void> leaveVoiceRoom() async {
    final call = _activeVoiceCall;
    if (call == null) return;
    _voiceConnectionStatus = VoiceConnectionStatus.disconnecting;
    notifyListeners();
    try {
      await call.leave();
    } finally {
      await _voiceCallSubscription?.cancel();
      _voiceCallSubscription = null;
      _activeVoiceCall = null;
      _activeSpeakerUserId = null;
      _voiceMuted = false;
      _voiceConnectionStatus = VoiceConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  @override
  Future<void> setComposerTyping(bool typing) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null || room.isSpace) return;
    _typingStopTimer?.cancel();
    if (typing) {
      if (_typingRoomId != room.id) {
        final oldRoom = _matrix.getRoomById(_typingRoomId ?? '');
        if (oldRoom != null) unawaited(oldRoom.setTyping(false));
      }
      _typingRoomId = room.id;
      await room.setTyping(true, timeout: 5000);
      _typingStopTimer = Timer(const Duration(seconds: 4), () {
        unawaited(setComposerTyping(false));
      });
    } else {
      if (_typingRoomId == room.id) await room.setTyping(false);
      _typingRoomId = null;
    }
  }

  Future<void> _notifyNewMessages() async {
    if (!_matrix.isLogged()) return;
    final rooms = _joinedRooms.where((room) => !room.isSpace);
    if (!_notificationsPrimed) {
      for (final room in rooms) {
        final eventId = room.lastEvent?.eventId;
        if (eventId != null) _lastNotificationEventIds[room.id] = eventId;
      }
      _notificationsPrimed = true;
      return;
    }
    for (final room in rooms) {
      final event = room.lastEvent;
      if (event == null ||
          _lastNotificationEventIds[room.id] == event.eventId) {
        continue;
      }
      _lastNotificationEventIds[room.id] = event.eventId;
      if (room.id == _selectedRoomId ||
          event.senderId == _matrix.userID ||
          room.pushRuleState == PushRuleState.dontNotify ||
          (room.pushRuleState == PushRuleState.mentionsOnly &&
              room.highlightCount == 0)) {
        continue;
      }
      var displayEvent = event;
      if (event.type == EventTypes.Encrypted && _matrix.encryption != null) {
        try {
          displayEvent = await _matrix.encryption!.decryptRoomEvent(event);
        } catch (_) {
          // A key arriving later will still update the room preview. The
          // notification must remain useful without delaying sync forever.
        }
      }
      final sender = event.senderFromMemoryOrFallback.calcDisplayname();
      final notificationBody = !_notificationPreviewsEnabled
          ? 'New message'
          : displayEvent.type == EventTypes.Message
          ? displayEvent.calcUnlocalizedBody(
              hideReply: true,
              hideEdit: true,
              plaintextBody: true,
            )
          : 'New room activity';
      await _notifications.show(
        title: '$sender in ${room.getLocalizedDisplayname()}',
        body: notificationBody,
      );
    }
  }

  void _loadSettings() {
    final content = _matrix.accountData[_settingsAccountDataType]?.content;
    _notificationPreviewsEnabled =
        content?.tryGet<bool>('notification_previews') ?? true;
  }

  @override
  Future<void> setNotificationPreviewsEnabled(bool enabled) async {
    if (_matrix.userID == null) return;
    final existing = _matrix.accountData[_settingsAccountDataType]?.content;
    try {
      await _matrix.setAccountData(_matrix.userID!, _settingsAccountDataType, {
        ...?existing,
        'notification_previews': enabled,
      });
      _notificationPreviewsEnabled = enabled;
      notifyListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
    }
  }

  @override
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  Future<void> refreshEncryptionSetup() async {
    if (_client == null || !_matrix.isLogged()) return;
    _encryptionSetup = const EncryptionSetupState(
      status: EncryptionSetupStatus.loading,
    );
    notifyListeners();
    try {
      final encryption = _matrix.encryption;
      if (encryption == null) {
        _encryptionSetup = const EncryptionSetupState(
          status: EncryptionSetupStatus.unavailable,
          message: 'End-to-end encryption is unavailable on this device.',
        );
      } else {
        final state = await _matrix.getCryptoIdentityState();
        final ownDevice = _matrix
            .userDeviceKeys[_matrix.userID]
            ?.deviceKeys[_matrix.deviceID];
        final deviceVerified = ownDevice?.verified ?? false;
        final hasSecureStorage = encryption.ssss.defaultKeyId != null;
        final status = state.initialized
            ? state.connected && deviceVerified
                  ? EncryptionSetupStatus.ready
                  : EncryptionSetupStatus.needsRecovery
            : hasSecureStorage ||
                  state.keyBackupEnabled ||
                  state.crossSigningEnabled
            ? EncryptionSetupStatus.needsRepair
            : EncryptionSetupStatus.needsSetup;
        _encryptionSetup = EncryptionSetupState(
          status: status,
          keyBackupEnabled: state.keyBackupEnabled,
          crossSigningEnabled: state.crossSigningEnabled,
          deviceVerified: deviceVerified,
        );
      }
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: EncryptionSetupStatus.error,
        message: _friendlyError(exception),
      );
    }
    notifyListeners();
  }

  @override
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase) async {
    final credential = recoveryKeyOrPassphrase.trim();
    if (credential.isEmpty) throw ArgumentError('Enter a recovery key.');
    try {
      final current = await _matrix.getCryptoIdentityState();
      if (current.initialized) {
        if (!current.connected) {
          await _matrix.restoreCryptoIdentity(credential);
        } else {
          await _matrix.encryption!.crossSigning.selfSign(
            keyOrPassphrase: credential,
          );
        }
      } else {
        await _matrix.initCryptoIdentity(
          reuseExistingStorageRecoveryKeyOrPassphrase: credential,
          wipeSecureStorage: false,
          wipeKeyBackup: false,
          wipeCrossSigning: false,
          setupMasterKey: !current.crossSigningEnabled,
          setupSelfSigningKey: !current.crossSigningEnabled,
          setupUserSigningKey: !current.crossSigningEnabled,
          setupOnlineKeyBackup: !current.keyBackupEnabled,
        );
      }
      await refreshEncryptionSetup();
      unawaited(_refreshRoomMetadata());
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: _encryptionSetup.status,
        keyBackupEnabled: _encryptionSetup.keyBackupEnabled,
        crossSigningEnabled: _encryptionSetup.crossSigningEnabled,
        deviceVerified: _encryptionSetup.deviceVerified,
        message: _friendlyError(exception),
      );
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<String> createEncryptionSetup() async {
    try {
      final current = await _matrix.getCryptoIdentityState();
      if (current.initialized ||
          _matrix.encryption?.ssss.defaultKeyId != null) {
        throw StateError(
          'Existing encrypted identity data was found. Recover it instead of replacing it.',
        );
      }
      final recoveryKey = await _matrix.initCryptoIdentity(
        keyName: 'Deltiecord recovery key',
        wipeSecureStorage: false,
        wipeKeyBackup: false,
        wipeCrossSigning: false,
      );
      await refreshEncryptionSetup();
      return recoveryKey;
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: _encryptionSetup.status,
        keyBackupEnabled: _encryptionSetup.keyBackupEnabled,
        crossSigningEnabled: _encryptionSetup.crossSigningEnabled,
        deviceVerified: _encryptionSetup.deviceVerified,
        message: _friendlyError(exception),
      );
      notifyListeners();
      rethrow;
    }
  }

  @override
  void selectSpace(String? spaceId) {
    if (_selectedSpaceId == spaceId) return;
    _selectedSpaceId = spaceId;
    _selectedRoomId = null;
    _closeTimeline();
    notifyListeners();
  }

  @override
  Future<void> selectRoom(String roomId) async {
    if (_selectedRoomId == roomId && _timeline != null) return;
    await _closeTimeline();
    final generation = _timelineGeneration;
    _selectedRoomId = roomId;
    _timelineLoading = true;
    _error = null;
    notifyListeners();
    try {
      final room = _matrix.getRoomById(roomId);
      if (room == null) throw StateError('That room is no longer available.');
      await room.postLoad();
      if (_presentationFor(room) == RoomPresentation.voice) {
        _timelineLoading = false;
        notifyListeners();
        return;
      }
      await _loadRoomBackupKeys(room);
      if (!_isCurrentSelection(roomId, generation)) return;
      final timeline = await room.getTimeline(
        onUpdate: () => _onTimelineUpdate(generation),
      );
      if (!_isCurrentSelection(roomId, generation)) {
        timeline.cancelSubscriptions();
        return;
      }
      _timeline = timeline;
      _captureFirstUnread(room, timeline);
      await _decryptTimelineEvents(timeline);
      if (!_isCurrentTimeline(timeline, generation)) return;
      await _hydrateTimelineMetadata(timeline);
      if (!_isCurrentTimeline(timeline, generation)) return;
      timeline.requestKeys(tryOnlineBackup: true, onlineKeyBackupOnly: false);
      await _markSelectedRoomRead();
    } catch (exception) {
      if (_isCurrentSelection(roomId, generation)) {
        _error = _friendlyError(exception);
      }
    } finally {
      if (_isCurrentSelection(roomId, generation)) {
        _timelineLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  ) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is no longer available.');
    try {
      await _matrix.setRoomStateWithKey(
        room.id,
        _roomPresentationEventType,
        '',
        {'kind': presentation.name},
      );
      _roomPresentationOverrides[roomId] = presentation;
      if (roomId == _selectedRoomId) {
        await _closeTimeline();
        _selectedRoomId = null;
        await selectRoom(roomId);
      }
      notifyListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> createRoom({
    required String name,
    required RoomPresentation presentation,
  }) async {
    _error = null;
    try {
      final roomId = await _matrix.createRoom(
        name: name.trim(),
        preset: CreateRoomPreset.privateChat,
        visibility: Visibility.private,
      );
      await _matrix.waitForRoomInSync(roomId, join: true);
      final room = _matrix.getRoomById(roomId);
      if (room == null) {
        throw StateError('The new room did not arrive in sync.');
      }
      if (_selectedSpaceId case final spaceId?) {
        await _matrix.getRoomById(spaceId)?.setSpaceChild(roomId);
      }
      await setRoomPresentation(roomId, presentation);
      await selectRoom(roomId);
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
    }
  }

  @override
  Future<void> renameRoom(String roomId, String name) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null || name.trim().isEmpty) return;
    try {
      await room.setName(name.trim());
    } catch (exception) {
      _error = _friendlyError(exception);
    }
    notifyListeners();
  }

  @override
  Future<void> setSelectedRoomMuted(bool muted) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) return;
    try {
      await room.setPushRuleState(
        muted ? PushRuleState.dontNotify : PushRuleState.notify,
      );
      notifyListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
    }
  }

  void _captureFirstUnread(Room room, Timeline timeline) {
    if (!room.hasNewMessages) {
      _firstUnreadEventIds[room.id] = null;
      return;
    }
    final markerId =
        room.receiptState.global.latestOwnReceipt?.eventId ??
        (room.fullyRead.isEmpty ? null : room.fullyRead);
    final markerIndex = markerId == null
        ? timeline.events.length
        : timeline.events.indexWhere((event) => event.eventId == markerId);
    final oldestUnreadIndex = markerIndex <= 0
        ? null
        : markerIndex > timeline.events.length
        ? timeline.events.length - 1
        : markerIndex - 1;
    _firstUnreadEventIds[room.id] = oldestUnreadIndex == null
        ? null
        : timeline.events[oldestUnreadIndex].eventId;
  }

  @override
  Future<void> loadMoreHistory() async {
    final timeline = _timeline;
    if (timeline == null || _historyLoading || !timeline.canRequestHistory) {
      return;
    }
    _historyLoading = true;
    notifyListeners();
    try {
      await timeline.requestHistory(historyCount: 50);
      if (!identical(timeline, _timeline)) return;
      await _decryptTimelineEvents(timeline);
      if (!identical(timeline, _timeline)) return;
      await _hydrateTimelineMetadata(timeline);
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _historyLoading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> sendMessage(
    String text, {
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) async {
    final value = text.trim();
    if (value.isEmpty || _selectedRoomId == null) return;
    try {
      final room = _matrix.getRoomById(_selectedRoomId!);
      if (room == null) throw StateError('The selected room is unavailable.');
      await _prepareEncryptedSend(room);
      final replyEvent = replyToMessageId == null
          ? null
          : _eventById(replyToMessageId);
      if (formattedBody == null || formattedBody.isEmpty) {
        await room.sendTextEvent(
          value,
          inReplyTo: replyEvent,
          editEventId: editMessageId,
        );
      } else {
        await room.sendEvent(
          {
            'msgtype': MessageTypes.Text,
            'body': value,
            'format': 'org.matrix.custom.html',
            'formatted_body': formattedBody,
            ..._mentionsFor(value, replyEvent),
          },
          inReplyTo: replyEvent,
          editEventId: editMessageId,
        );
      }
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
      rethrow;
    }
  }

  Map<String, Object> _mentionsFor(String text, Event? replyEvent) {
    final userIds = RegExp(r'@[A-Za-z0-9._=\-/]+:[^\s<>()]+')
        .allMatches(text)
        .map((match) => match.group(0)!)
        .where((userId) => userId != _matrix.userID)
        .toSet();
    if (replyEvent != null && replyEvent.senderId != _matrix.userID) {
      userIds.add(replyEvent.senderId);
    }
    final room = RegExp(r'(^|\s)@room(?=\s|$)').hasMatch(text);
    if (userIds.isEmpty && !room) return const {};
    return {
      'm.mentions': {
        if (userIds.isNotEmpty) 'user_ids': userIds.toList(growable: false),
        if (room) 'room': true,
      },
    };
  }

  Event? _eventById(String eventId) {
    final timeline = _timeline;
    if (timeline == null) return null;
    for (final event in timeline.events) {
      if (event.eventId == eventId) return event;
    }
    return null;
  }

  @override
  Future<void> redactMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null) throw StateError('That message is no longer available.');
    if (!event.canRedact) throw StateError('You cannot delete that message.');
    try {
      await event.redactEvent(redactAllEdits: true);
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> retryMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || !event.status.isError) {
      throw StateError('That failed message is no longer available.');
    }
    try {
      await _prepareEncryptedSend(event.room);
      await event.sendAgain();
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> cancelPendingMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || event.status.isSent) return;
    await event.cancelSend();
    notifyListeners();
  }

  @override
  Future<void> toggleReaction(String messageId, String key) async {
    final value = key.trim();
    if (value.isEmpty) return;
    final timeline = _timeline;
    final event = _eventById(messageId);
    if (timeline == null || event == null) {
      throw StateError('That message is no longer available.');
    }
    try {
      final ownReaction = event
          .aggregatedEvents(timeline, RelationshipTypes.reaction)
          .where(
            (reaction) =>
                reaction.senderId == _matrix.userID &&
                !reaction.redacted &&
                reaction.content
                        .tryGetMap<String, Object?>('m.relates_to')
                        ?.tryGet<String>('key') ==
                    value,
          )
          .firstOrNull;
      if (ownReaction != null) {
        await ownReaction.redactEvent();
      } else {
        await _prepareEncryptedSend(event.room);
        await event.room.sendReaction(event.eventId, value);
      }
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? replyToMessageId,
  }) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) throw StateError('The selected room is unavailable.');
    try {
      await _validateUploadSize(attachment.bytes.length);
      await _prepareEncryptedSend(room);
      final replyEvent = replyToMessageId == null
          ? null
          : _eventById(replyToMessageId);
      final file = MatrixFile.fromMimeType(
        bytes: attachment.bytes,
        name: attachment.name,
        mimeType: attachment.mimeType,
      );
      await room.sendFileEvent(
        file,
        inReplyTo: replyEvent,
        // Re-encoding large images here is CPU-heavy and stalls Flutter's UI
        // isolate. The SDK still generates a thumbnail, but uploads the
        // original image without a redundant full-resolution shrink pass.
        shrinkImageMaxDimension: null,
        extraContent:
            attachment.spoiler || attachment.caption?.trim().isNotEmpty == true
            ? {
                if (attachment.caption?.trim().isNotEmpty == true) ...{
                  'body': attachment.caption!.trim(),
                  'filename': attachment.name,
                },
                // MSC4193's unstable key is used by existing clients. Keep the
                // stable-looking key too so migration does not require a resend.
                if (attachment.spoiler) ...{
                  'page.codeberg.everypizza.msc4193.spoiler': true,
                  'm.spoiler': true,
                },
              }
            : null,
      );
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _refreshMediaConfig() async {
    try {
      _maximumUploadBytes = (await _matrix.getConfig()).mUploadSize;
    } catch (_) {
      // The endpoint is advisory and not exposed by every homeserver. The
      // upload request itself remains the authoritative fallback.
    }
  }

  Future<void> _validateUploadSize(int byteLength) async {
    if (_maximumUploadBytes == null) await _refreshMediaConfig();
    final limit = _maximumUploadBytes;
    if (limit == null || byteLength <= limit) return;
    throw StateError(
      'This file is ${_formatByteSize(byteLength)}, but the homeserver allows '
      'uploads up to ${_formatByteSize(limit)}.',
    );
  }

  String _formatByteSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';
    return '${(mib / 1024).toStringAsFixed(1)} GiB';
  }

  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async {
    final event = _eventById(messageId);
    if (event == null || !event.hasAttachment) {
      throw StateError('That attachment is no longer available.');
    }
    final file = await event.downloadAndDecryptAttachment(
      getThumbnail: thumbnail && event.hasThumbnail,
    );
    return file.bytes;
  }

  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || !event.hasAttachment) {
      return null;
    }
    final cached = _mediaPlaybackSources[messageId];
    if (cached != null) return cached;
    if (event.isAttachmentEncrypted) {
      final file = event.content.tryGetMap<String, Object?>('file');
      final mxc = Uri.tryParse(file?.tryGet<String>('url') ?? '');
      final keyText = file
          ?.tryGetMap<String, Object?>('key')
          ?.tryGet<String>('k');
      final ivText = file?.tryGet<String>('iv');
      final size = event.infoMap.tryGet<int>('size');
      final accessToken = _matrix.accessToken;
      if (mxc == null ||
          !mxc.isScheme('mxc') ||
          keyText == null ||
          ivText == null ||
          size == null ||
          size <= 0 ||
          accessToken == null) {
        return null;
      }
      final upstream = await mxc.getDownloadUri(_matrix, skipScanner: true);
      final localUri = await _mediaRangeProxy.register(
        upstream: upstream,
        accessToken: accessToken,
        key: base64Url.decode(base64.normalize(keyText)),
        iv: base64.decode(base64.normalize(ivText)),
        size: size,
        mimeType: event.attachmentMimetype,
      );
      final source = MediaPlaybackSource(uri: localUri, headers: const {});
      _mediaPlaybackSources[messageId] = source;
      return source;
    }
    final uri = await event.getAttachmentUri(skipScanner: false);
    if (uri == null) return null;
    final source = MediaPlaybackSource(
      uri: uri,
      headers: {
        if (_matrix.accessToken case final token?)
          'Authorization': 'Bearer $token',
      },
    );
    _mediaPlaybackSources[messageId] = source;
    return source;
  }

  Future<void> _prepareEncryptedSend(Room room) async {
    if (!room.encrypted || _outboundSessionsReset.contains(room.id)) return;
    final keyManager = _matrix.encryption?.keyManager;
    if (keyManager == null) {
      throw StateError('End-to-end encryption is not ready.');
    }
    // Sessions created under the earlier verified-only policy remember the
    // excluded devices. Rotate once so all current non-blocked devices receive
    // the new Megolm session before ciphertext is sent.
    await keyManager.loadOutboundGroupSession(room.id);
    await keyManager.clearOrUseOutboundGroupSession(room.id, wipe: true);
    _outboundSessionsReset.add(room.id);
  }

  bool _isCurrentSelection(String roomId, int generation) =>
      generation == _timelineGeneration && roomId == _selectedRoomId;

  bool _isCurrentTimeline(Timeline timeline, int generation) =>
      generation == _timelineGeneration && identical(timeline, _timeline);

  void _onTimelineUpdate(int generation) {
    if (generation != _timelineGeneration) return;
    notifyListeners();
    final timeline = _timeline;
    if (timeline != null) {
      unawaited(_hydrateCurrentTimeline(timeline, generation));
      unawaited(_markSelectedRoomRead());
    }
  }

  Future<void> _hydrateCurrentTimeline(
    Timeline timeline,
    int generation,
  ) async {
    if (!_isCurrentTimeline(timeline, generation)) return;
    await _hydrateTimelineMetadata(timeline);
  }

  Future<void> _markSelectedRoomRead() async {
    final initialTimeline = _timeline;
    if (initialTimeline == null || initialTimeline.room.id != _selectedRoomId) {
      return;
    }
    final roomId = initialTimeline.room.id;
    if (_roomsMarkingRead.contains(roomId)) return;
    _roomsMarkingRead.add(roomId);
    try {
      while (identical(initialTimeline, _timeline) &&
          roomId == _selectedRoomId) {
        String? newestSyncedEventId;
        for (final event in initialTimeline.events) {
          if (event.status.isSynced) {
            newestSyncedEventId = event.eventId;
            break;
          }
        }
        if (newestSyncedEventId == null ||
            newestSyncedEventId == _lastMarkedReadEventIds[roomId]) {
          return;
        }
        // Timeline.setReadMarker sends both the fully-read marker and the
        // account's configured public/private receipt for this event.
        await initialTimeline.setReadMarker(eventId: newestSyncedEventId);
        _lastMarkedReadEventIds[roomId] = newestSyncedEventId;
      }
    } catch (_) {
      // Receipt failures are non-fatal and will be retried on the next update.
    } finally {
      _roomsMarkingRead.remove(roomId);
    }
  }

  RoomSummary _roomSummary(Room room) => RoomSummary(
    id: room.id,
    name: room.getLocalizedDisplayname(),
    lastMessage: _eventPreview(room.lastEvent),
    unreadCount: room.notificationCount,
    usesChannelIcon: _selectedSpaceId != null,
    presentation: _presentationFor(room),
    voiceParticipants: _voiceParticipants(room),
    avatarBytes: _avatarBytes[room.id],
  );

  RoomPresentation _presentationFor(Room room) {
    final overridden = _roomPresentationOverrides[room.id];
    if (overridden != null) return overridden;
    final kind = room
        .getState(_roomPresentationEventType)
        ?.content
        .tryGet<String>('kind');
    return kind == RoomPresentation.voice.name
        ? RoomPresentation.voice
        : RoomPresentation.text;
  }

  List<VoiceParticipantSummary> _voiceParticipants(Room room) {
    final memberStates = room.states[EventTypes.GroupCallMember];
    if (memberStates == null) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final participants = <String, VoiceParticipantSummary>{};
    for (final state in memberStates.values) {
      final memberships = state.content.tryGetList('memberships') ?? const [];
      final active = memberships.whereType<Map>().any((membership) {
        final expires = membership['expires_ts'];
        return expires is int && expires > now;
      });
      if (!active) continue;
      final userId = state.senderId;
      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      participants[userId] = VoiceParticipantSummary(
        userId: userId,
        displayName: user.calcDisplayname(),
        avatarBytes: _senderAvatarBytes['${room.id}|$userId'],
        speaking: userId == _activeSpeakerUserId,
      );
    }
    final result = participants.values.toList(growable: false);
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  String _eventPreview(Event? event) {
    if (event == null) return 'No messages yet';
    final decrypted = _decryptedPreviews[event.eventId];
    if (decrypted != null) return decrypted;
    if (event.type == EventTypes.Encrypted) return 'Encrypted message';
    if (event.type != EventTypes.Message) return 'Room activity';
    return _messagePreview(event);
  }

  String _messagePreview(Event event) => event.calcUnlocalizedBody(
    hideReply: true,
    hideEdit: true,
    plaintextBody: true,
  );

  Future<void> _refreshRoomMetadata() async {
    _roomMetadataRefreshRequested = true;
    if (_refreshingRoomMetadata || !_matrix.isLogged()) return;
    _refreshingRoomMetadata = true;
    var changed = false;
    try {
      do {
        _roomMetadataRefreshRequested = false;
        for (final room in _joinedRooms) {
          try {
            await room.postLoad();
            if (!room.isSpace) await room.loadHeroUsers();
            changed = await _refreshAvatar(room) || changed;
            if (!room.isSpace) {
              changed = await _refreshPreview(room) || changed;
            }
          } catch (_) {
            // One unavailable avatar or key must not block the other rooms.
          }
        }
      } while (_roomMetadataRefreshRequested && _matrix.isLogged());
    } finally {
      _refreshingRoomMetadata = false;
      if (changed) notifyListeners();
    }
  }

  Future<bool> _refreshAvatar(Room room) async {
    final avatar = room.avatar;
    if (_avatarUris.containsKey(room.id) && _avatarUris[room.id] == avatar) {
      return false;
    }
    _avatarUris[room.id] = avatar;
    _avatarBytes.remove(room.id);
    if (avatar == null || !avatar.isScheme('mxc')) return true;
    final mediaId = avatar.pathSegments.join('/');
    if (mediaId.isEmpty) return true;
    final response = await _matrix.getContentThumbnail(
      avatar.host,
      mediaId,
      96,
      96,
      method: Method.crop,
      animated: false,
    );
    _avatarBytes[room.id] = response.data;
    return true;
  }

  Future<bool> _refreshPreview(Room room) async {
    final event = room.lastEvent;
    if (event == null) return false;
    if (event.type == EventTypes.Message) {
      final body = _messagePreview(event);
      if (_decryptedPreviews[event.eventId] == body) return false;
      _decryptedPreviews[event.eventId] = body;
      return true;
    }
    if (event.type != EventTypes.Encrypted || _matrix.encryption == null) {
      return false;
    }
    final encrypted = event.parsedRoomEncryptedContent;
    final sessionId = encrypted.sessionId;
    final keyManager = _matrix.encryption!.keyManager;
    if (sessionId != null &&
        keyManager.enabled &&
        await keyManager.isCached()) {
      try {
        await keyManager.loadSingleKey(room.id, sessionId);
      } on MatrixException catch (exception) {
        if (exception.error != MatrixError.M_NOT_FOUND) rethrow;
      }
    }
    final decrypted = await _matrix.encryption!.decryptRoomEvent(event);
    if (decrypted.type != EventTypes.Message) return false;
    final body = _messagePreview(decrypted);
    if (_decryptedPreviews[event.eventId] == body) return false;
    _decryptedPreviews[event.eventId] = body;
    return true;
  }

  Future<void> _loadRoomBackupKeys(Room room) async {
    if (!room.encrypted || _loadedBackupRoomIds.contains(room.id)) return;
    final keyManager = _matrix.encryption?.keyManager;
    if (keyManager == null || !keyManager.enabled) return;
    if (!await keyManager.isCached()) return;
    try {
      await keyManager.loadAllKeysFromRoom(room.id);
      _loadedBackupRoomIds.add(room.id);
    } on MatrixException catch (exception) {
      if (exception.error != MatrixError.M_NOT_FOUND) rethrow;
    }
  }

  Future<void> _decryptTimelineEvents(Timeline timeline) async {
    final encryption = _matrix.encryption;
    if (encryption == null) return;
    await _matrix.database.transaction(() async {
      for (var index = 0; index < timeline.events.length; index++) {
        final event = timeline.events[index];
        if (event.type != EventTypes.Encrypted) continue;
        timeline.events[index] = await encryption.decryptRoomEvent(
          event,
          store: true,
          updateType: EventUpdateType.history,
        );
      }
    });
    notifyListeners();
  }

  Future<void> _hydrateTimelineMetadata(Timeline timeline) async {
    await _hydrateSenderAvatars(timeline);
    await _hydrateReplies(timeline);
    await _hydrateLinkPreviews(timeline);
    notifyListeners();
  }

  static final _webUrlPattern = RegExp(r'https?://[^\s<>]+');

  Future<void> _hydrateLinkPreviews(Timeline timeline) async {
    for (final event in timeline.events) {
      if (_linkPreviews.containsKey(event.eventId) ||
          event.type != EventTypes.Message ||
          event.hasAttachment) {
        continue;
      }
      final match = _webUrlPattern.firstMatch(
        event.calcUnlocalizedBody(
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
        ),
      );
      final rawUrl = match?.group(0)?.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
      final url = rawUrl == null ? null : Uri.tryParse(rawUrl);
      if (url == null) {
        _linkPreviews[event.eventId] = null;
        continue;
      }
      // The standard endpoint lets the homeserver apply its SSRF protections
      // and cache metadata consistently with other Matrix clients.
      try {
        final preview = await _matrix.getUrlPreview(
          url,
          ts: event.originServerTs.millisecondsSinceEpoch,
        );
        final properties = preview.additionalProperties;
        Uint8List? imageBytes;
        final image = preview.ogImage;
        if (image != null) {
          imageBytes = await _previewImageBytes(image);
        }
        Uri? propertyUri(String key) {
          final value = properties[key];
          return value is String ? Uri.tryParse(value) : null;
        }

        String? propertyString(String key) {
          final value = properties[key];
          return value is String && value.trim().isNotEmpty
              ? value.trim()
              : null;
        }

        final result = LinkPreview(
          url: url,
          title: propertyString('og:title'),
          description: propertyString('og:description'),
          siteName: propertyString('og:site_name'),
          imageBytes: imageBytes,
          videoUrl: propertyUri('og:video') ?? propertyUri('og:video:url'),
        );
        _linkPreviews[event.eventId] =
            result.title == null &&
                result.description == null &&
                result.imageBytes == null &&
                result.videoUrl == null
            ? await _directLinkPreview(url)
            : result;
      } catch (_) {
        _linkPreviews[event.eventId] = await _directLinkPreview(url);
      }
    }
  }

  Future<LinkPreview?> _directLinkPreview(Uri url) async {
    try {
      final fxPreview = await _fxTwitterPreview(url);
      if (fxPreview != null) return fxPreview;
      if (!await _isPublicWebUrl(url)) return null;
      final request = await _previewHttpClient.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'text/html');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > 2 * 1024 * 1024) {
        await response.drain<void>();
        return null;
      }
      final source = await utf8.decodeStream(response);
      final document = html_parser.parse(source);
      String? meta(String property) {
        final element =
            document.querySelector('meta[property="$property"]') ??
            document.querySelector('meta[name="$property"]');
        final content = element?.attributes['content']?.trim();
        return content == null || content.isEmpty ? null : content;
      }

      Uri? resolved(String? value) {
        if (value == null) return null;
        return url.resolve(value);
      }

      final imageUrl = resolved(meta('og:image') ?? meta('twitter:image'));
      final videoUrl = resolved(
        meta('og:video:secure_url') ?? meta('og:video:url') ?? meta('og:video'),
      );
      final pageTitle = document.querySelector('title')?.text.trim();
      final title =
          meta('og:title') ??
          meta('twitter:title') ??
          (pageTitle?.isNotEmpty == true ? pageTitle : null);
      final description =
          meta('og:description') ??
          meta('twitter:description') ??
          meta('description');
      if (title == null &&
          description == null &&
          imageUrl == null &&
          videoUrl == null) {
        return null;
      }
      return LinkPreview(
        url: url,
        title: title,
        description: description,
        siteName: meta('og:site_name') ?? url.host,
        imageBytes: imageUrl == null
            ? null
            : await _previewImageBytes(imageUrl),
        videoUrl: videoUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<LinkPreview?> _fxTwitterPreview(Uri url) async {
    if (!{
      'fxtwitter.com',
      'www.fxtwitter.com',
      'fixupx.com',
    }.contains(url.host)) {
      return null;
    }
    final match = RegExp(r'/status/(\d+)').firstMatch(url.path);
    final statusId = match?.group(1);
    if (statusId == null) return null;
    final apiUrl = Uri.https('api.fxtwitter.com', '/status/$statusId');
    final request = await _previewHttpClient.getUrl(apiUrl);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) return null;
    final json = jsonDecode(await utf8.decodeStream(response));
    if (json is! Map) return null;
    final tweet = json['tweet'];
    if (tweet is! Map) return null;
    final media = tweet['media'];
    final all = media is Map ? media['all'] : null;
    final firstMedia = all is List && all.isNotEmpty ? all.first : null;
    final mediaMap = firstMedia is Map ? firstMedia : null;
    final thumbnail = Uri.tryParse(
      mediaMap?['thumbnail_url']?.toString() ?? '',
    );
    final mediaUrl = Uri.tryParse(mediaMap?['url']?.toString() ?? '');
    final author = tweet['author'];
    final authorName = author is Map ? author['name']?.toString() : null;
    return LinkPreview(
      url: url,
      title: authorName == null ? 'Post on X' : '$authorName on X',
      description: tweet['text']?.toString(),
      siteName: 'X via FxTwitter',
      imageBytes: thumbnail?.hasScheme == true
          ? await _previewImageBytes(thumbnail!)
          : null,
      videoUrl: mediaMap?['type'] == 'video' && mediaUrl?.hasScheme == true
          ? mediaUrl
          : null,
    );
  }

  Future<Uint8List?> _previewImageBytes(Uri uri) async {
    if (uri.isScheme('mxc')) {
      final thumbnail = await _matrix.getContentThumbnail(
        uri.host,
        uri.pathSegments.join('/'),
        640,
        360,
        method: Method.scale,
        animated: true,
      );
      return thumbnail.data;
    }
    if (!await _isPublicWebUrl(uri)) return null;
    final request = await _previewHttpClient.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > 8 * 1024 * 1024) {
      await response.drain<void>();
      return null;
    }
    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
      if (all.length + chunk.length > 8 * 1024 * 1024) {
        throw const HttpException('Preview image is too large.');
      }
      return all..addAll(chunk);
    });
    return Uint8List.fromList(bytes);
  }

  Future<bool> _isPublicWebUrl(Uri uri) async {
    if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      return false;
    }
    if (uri.host == 'localhost' || uri.host.endsWith('.localhost')) {
      return false;
    }
    final addresses = await InternetAddress.lookup(uri.host);
    return addresses.isNotEmpty &&
        addresses.every((address) {
          if (address.isLoopback ||
              address.isLinkLocal ||
              address.isMulticast) {
            return false;
          }
          final raw = address.rawAddress;
          if (address.type == InternetAddressType.IPv4) {
            return !(raw[0] == 10 ||
                raw[0] == 127 ||
                (raw[0] == 169 && raw[1] == 254) ||
                (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) ||
                (raw[0] == 192 && raw[1] == 168));
          }
          return !(raw[0] == 0xfc || raw[0] == 0xfd);
        });
  }

  Future<void> _hydrateSenderAvatars(Timeline timeline) async {
    for (final event in timeline.events) {
      final sender = event.senderFromMemoryOrFallback;
      final avatar = sender.avatarUrl;
      if (_senderAvatarUris.containsKey(event.senderId) &&
          _senderAvatarUris[event.senderId] == avatar) {
        continue;
      }
      _senderAvatarUris[event.senderId] = avatar;
      _senderAvatarBytes.remove(event.senderId);
      if (avatar == null || !avatar.isScheme('mxc')) continue;
      try {
        final response = await _matrix.getContentThumbnail(
          avatar.host,
          avatar.pathSegments.join('/'),
          64,
          64,
          method: Method.crop,
          animated: false,
        );
        _senderAvatarBytes[event.senderId] = response.data;
      } catch (_) {
        // Missing profile media should fall back to an initial.
      }
    }
  }

  Future<void> _hydrateReplies(Timeline timeline) async {
    for (final event in timeline.events) {
      if (event.type != EventTypes.Message ||
          event.inReplyToEventId() == null ||
          _replyPreviews.containsKey(event.eventId)) {
        continue;
      }
      var repliedTo = await event.getReplyEvent(timeline);
      if (repliedTo == null) continue;
      if (repliedTo.type == EventTypes.Encrypted &&
          _matrix.encryption != null) {
        repliedTo = await _matrix.encryption!.decryptRoomEvent(repliedTo);
      }
      if (repliedTo.type != EventTypes.Message) continue;
      _replyPreviews[event.eventId] = ReplyPreview(
        sender: repliedTo.senderFromMemoryOrFallback.calcDisplayname(),
        body: repliedTo.calcUnlocalizedBody(
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
        ),
      );
    }
  }

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
    unawaited(leaveVoiceRoom());
    _timeline?.cancelSubscriptions();
    _syncSubscription?.cancel();
    _loginSubscription?.cancel();
    _client?.dispose();
    unawaited(_mediaRangeProxy.close());
    _previewHttpClient.close(force: true);
    super.dispose();
  }
}
