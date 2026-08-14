import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'matrix_client_factory.dart';
import 'media_range_proxy.dart';

class MatrixBackend extends ChatBackend {
  Client? _client;
  Timeline? _timeline;
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
  final Set<String> _outboundSessionsReset = {};
  bool _refreshingRoomMetadata = false;
  bool _roomMetadataRefreshRequested = false;
  final Set<String> _roomsMarkingRead = {};
  final Map<String, String> _lastMarkedReadEventIds = {};
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
  List<MentionSuggestion> get mentionSuggestions {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    final suggestions = room
        .getParticipants()
        .map(
          (user) => MentionSuggestion(
            userId: user.id,
            displayName: user.calcDisplayname(),
          ),
        )
        .toList(growable: false);
    suggestions.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return suggestions;
  }

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
  List<ChatMessage> get messages {
    final timeline = _timeline;
    if (timeline == null) return const [];
    return timeline.events
        .where(
          (event) =>
              event.type == EventTypes.Message ||
              event.type == EventTypes.Encrypted,
        )
        .where((event) => event.relationshipType != RelationshipTypes.edit)
        .map((event) {
          final displayEvent = event.type == EventTypes.Message
              ? event.getDisplayEvent(timeline)
              : event;
          return ChatMessage(
            id: event.eventId,
            sender: event.senderFromMemoryOrFallback.calcDisplayname(),
            body: event.redacted
                ? 'Message deleted'
                : displayEvent.type == EventTypes.Encrypted
                ? 'Unable to decrypt this message'
                : displayEvent.calcUnlocalizedBody(
                    hideReply: true,
                    hideEdit: true,
                    plaintextBody: true,
                  ),
            timestamp: event.originServerTs,
            pending: event.status.isSending,
            failed: event.status.isError,
            own: event.senderId == _matrix.userID,
            canRedact: event.canRedact && !event.redacted,
            edited: displayEvent.eventId != event.eventId,
            redacted: event.redacted,
            reactions: _reactionSummaries(event, timeline),
            attachment: _attachmentFor(displayEvent),
            formattedBody: displayEvent.isRichMessage
                ? displayEvent.formattedText
                : null,
            reply: _replyPreviews[event.eventId],
            avatarBytes: _senderAvatarBytes[event.senderId],
          );
        })
        .toList(growable: false);
  }

  ChatAttachment? _attachmentFor(Event event) {
    if (!event.hasAttachment) return null;
    final kind = switch (event.messageType) {
      MessageTypes.Image => AttachmentKind.image,
      MessageTypes.Video => AttachmentKind.video,
      MessageTypes.Audio => AttachmentKind.audio,
      _ => AttachmentKind.file,
    };
    return ChatAttachment(
      kind: kind,
      name: event.content.tryGet<String>('filename') ?? event.body,
      mimeType: event.attachmentMimetype,
      size: event.infoMap.tryGet<int>('size'),
      encrypted: event.isAttachmentEncrypted,
      spoiler:
          event.content.tryGet<bool>(
                'page.codeberg.everypizza.msc4193.spoiler',
              ) ==
              true ||
          event.content.tryGet<bool>('m.spoiler') == true,
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
        notifyListeners();
        unawaited(_refreshRoomMetadata());
      });
      _loginSubscription = _matrix.onLoginStateChanged.stream.listen((_) {
        _status = _matrix.isLogged()
            ? SessionStatus.signedIn
            : SessionStatus.signedOut;
        notifyListeners();
      });
      await _matrix.init();
      _status = _matrix.isLogged()
          ? SessionStatus.signedIn
          : SessionStatus.signedOut;
      _error = null;
      if (_matrix.isLogged()) {
        unawaited(refreshEncryptionSetup());
        unawaited(_refreshRoomMetadata());
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
      _status = SessionStatus.signedIn;
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
      _outboundSessionsReset.clear();
      _roomsMarkingRead.clear();
      _lastMarkedReadEventIds.clear();
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
        shrinkImageMaxDimension: file is MatrixImageFile ? 2000 : null,
        extraContent: attachment.spoiler
            ? {
                // MSC4193's unstable key is used by existing clients. Keep the
                // stable-looking key too so migration does not require a resend.
                'page.codeberg.everypizza.msc4193.spoiler': true,
                'm.spoiler': true,
              }
            : null,
      );
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
      rethrow;
    }
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
    avatarBytes: _avatarBytes[room.id],
  );

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
    notifyListeners();
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
    _timeline?.cancelSubscriptions();
    _syncSubscription?.cancel();
    _loginSubscription?.cancel();
    _client?.dispose();
    unawaited(_mediaRangeProxy.close());
    super.dispose();
  }
}
