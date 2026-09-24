part of 'matrix_backend.dart';

/// Decrypts timeline events and progressively hydrates optional metadata.
///
/// Text is published before avatars, replies, and previews. Hydration passes
/// are serialized because sync bursts can otherwise duplicate network work and
/// let stale room results outlive a fast room switch.
extension _MatrixTimelineSupport on MatrixBackend {
  // Flutter's lazy sliver materializes only visible rows. Keep stable event
  // identities in that sliver instead of replacing both ends of a bounded UI
  // window; the latter made the scroll position irrecoverable after paging.
  List<Event> _timelineWindowEvents(Timeline timeline) => timeline.events;

  Future<void> _hydrateSenderAvatars(Timeline timeline) async {
    final missing = <(String, Uri)>[];
    final seen = <String>{};
    for (final event in _timelineWindowEvents(timeline)) {
      if (event.type == EventTypes.Message ||
          event.type == EventTypes.Encrypted ||
          event.type == EventTypes.Sticker) {
        unawaited(_refreshProfileForMessage(event, timeline.room));
      }
      if (!seen.add(event.senderId)) continue;
      final sender = event.senderFromMemoryOrFallback;
      final profile = _profileCache[event.senderId];
      // Room membership can lag behind the global profile, especially for our
      // own user immediately after login or an avatar change. Prefer the
      // shared profile cache so timeline hydration cannot evict an avatar that
      // is already visible in the user island and DM list.
      final avatar = profile != null ? profile.avatarUri : sender.avatarUrl;
      if (_senderAvatarUris.containsKey(event.senderId) &&
          _senderAvatarUris[event.senderId] == avatar &&
          _senderAvatarBytes[event.senderId] != null) {
        continue;
      }
      _senderAvatarUris[event.senderId] = avatar;
      _senderAvatarBytes.remove(event.senderId);
      if (avatar == null || !avatar.isScheme('mxc')) continue;

      final room = timeline.room;
      if (room.directChatMatrixID == event.senderId &&
          _avatarUris[room.id] == avatar) {
        final roomAvatar = _avatarBytes[room.id];
        if (roomAvatar != null) {
          _senderAvatarBytes[event.senderId] = roomAvatar;
          _senderAvatarBytes['${room.id}|${event.senderId}'] = roomAvatar;
          continue;
        }
      }

      if (profile?.avatarUri == avatar &&
          profile?.profile.avatarBytes != null) {
        final bytes = profile!.profile.avatarBytes!;
        _avatarMediaPool.seed(avatar, bytes, AvatarMediaPool.profileDimension);
        _senderAvatarBytes[event.senderId] = bytes;
        continue;
      }
      final pooled = _avatarMediaPool.peek(
        avatar,
        AvatarMediaPool.rowDimension,
      );
      if (pooled != null) {
        _senderAvatarBytes[event.senderId] = pooled;
        continue;
      }
      missing.add((event.senderId, avatar));
    }

    for (var start = 0; start < missing.length; start += 4) {
      final end = min(start + 4, missing.length);
      await Future.wait(
        missing.sublist(start, end).map((entry) async {
          try {
            final bytes = await _avatarMedia(
              entry.$2,
              AvatarMediaPool.rowDimension,
            );
            if (bytes != null && _senderAvatarUris[entry.$1] == entry.$2) {
              _senderAvatarBytes[entry.$1] = bytes;
            }
          } catch (_) {
            // Missing profile media should fall back to an initial.
          }
        }),
      );
      if (identical(_timeline, timeline)) _notifyBackendListeners();
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
      // Keep the original event ID as the navigation target, but render its
      // latest replacement so reply previews cannot preserve a stale body.
      final originalEventId = repliedTo.eventId;
      final displayEvent = repliedTo.getDisplayEvent(timeline);
      _replyPreviews[event.eventId] = ReplyPreview(
        eventId: originalEventId,
        senderId: displayEvent.senderId,
        sender: displayEvent.senderFromMemoryOrFallback.calcDisplayname(),
        body: displayEvent.calcUnlocalizedBody(
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
        ),
      );
    }
  }

  Future<void> _loadRoomBackupKeys(Room room, Timeline timeline) async {
    if (!room.encrypted) return;
    final keyManager = _matrix.encryption?.keyManager;
    if (keyManager == null || !keyManager.enabled) return;
    if (!await keyManager.isCached()) return;
    // Restore only sessions referenced by the loaded window, not years of room
    // history. The SDK handles older sessions as history is requested later.
    final sessions = <String>{
      for (final event in timeline.events)
        if (event.type == EventTypes.Encrypted)
          if (event.content['session_id'] case final String sessionId)
            sessionId,
    };
    for (final sessionId in sessions) {
      if (!identical(_timeline, timeline)) return;
      if (await keyManager.loadInboundGroupSession(room.id, sessionId) !=
          null) {
        continue;
      }
      try {
        await keyManager.loadSingleKey(room.id, sessionId);
      } on MatrixException catch (exception) {
        if (exception.error != MatrixError.M_NOT_FOUND) rethrow;
      }
      if (kIsWeb) await Future<void>.delayed(Duration.zero);
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
    _notifyBackendListeners();
  }

  Future<void> _hydrateTimelineMetadata(Timeline timeline) async {
    final retainedEventIds = timeline.events
        .map((event) => event.eventId)
        .toSet();
    retainedEventIds.addAll(_forumRoots.keys);
    for (final session in _threadSessions) {
      retainedEventIds.addAll(
        session._timeline?.events.map((event) => event.eventId) ??
            const <String>[],
      );
    }
    _replyPreviews.removeWhere(
      (eventId, _) => !retainedEventIds.contains(eventId),
    );
    _linkPreviews.removeWhere(
      (eventId, _) => !retainedEventIds.contains(eventId),
    );
    for (final eventId
        in _mediaPlaybackSources.keys
            .where((eventId) => !retainedEventIds.contains(eventId))
            .toList(growable: false)) {
      final source = _mediaPlaybackSources.remove(eventId);
      _mediaPlaybackReferences.remove(eventId);
      if (source != null) {
        releaseBrowserMediaUrl(source.uri);
        _mediaRangeProxy.unregister(source.uri);
      }
    }
    await Future.wait([
      _hydrateSenderAvatars(timeline),
      _hydrateReplies(timeline),
      _hydratePollResponses(timeline),
    ]);
    if (!identical(timeline, _timeline)) return;
    _notifyBackendListeners();
    await _hydrateLinkPreviews(timeline);
    if (!identical(timeline, _timeline)) return;
    _notifyBackendListeners();
  }

  Future<void> _hydratePollResponses(Timeline timeline) async {
    final pending = timeline.events.where(
      (event) =>
          event.type == PollEventContent.startType &&
          !_hydratedPollResponseIds.contains(event.eventId),
    );
    for (final event in pending) {
      try {
        await event.fetchPollResponses(timeline);
        _hydratedPollResponseIds.add(event.eventId);
      } catch (_) {
        // Polls remain usable with responses already present in the timeline;
        // a later hydration pass can retry a failed aggregation request.
      }
    }
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
    final timeline = _timeline;
    if (timeline != null) {
      _notifyBackendListeners();
      unawaited(_hydrateCurrentTimeline(timeline, generation));
      unawaited(_markSelectedRoomRead());
    }
  }

  Future<void> _refreshTimelineAfterResume() async {
    _resumeTimelineRefreshRequested = true;
    if (_resumeTimelineRefreshRunning || !_matrix.isLogged()) return;
    _resumeTimelineRefreshRunning = true;
    try {
      while (_resumeTimelineRefreshRequested && _matrix.isLogged()) {
        _resumeTimelineRefreshRequested = false;
        final timeline = _timeline;
        final generation = _timelineGeneration;
        if (timeline == null || !_isCurrentTimeline(timeline, generation)) {
          continue;
        }
        try {
          // oneShotSync joins an outstanding long poll, even with timeout=0.
          // Invalidate that suspended request through the SDK before restarting;
          // abortSync waits for its database transaction and rejects stale data.
          // Keep the same Timeline, listeners, and scroll anchor throughout.
          final client = _matrix;
          await client.abortSync();
          if (!identical(client, _client) || !client.isLogged()) return;
          final refresh = client.oneShotSync(timeout: Duration.zero);
          client.backgroundSync = true;
          await refresh;
        } catch (_) {
          // The normal sync loop owns reconnect/backoff. A resume refresh is a
          // best-effort nudge and must never replace its connection state.
        }
        if (_isCurrentTimeline(timeline, generation)) {
          _onTimelineUpdate(generation);
        }
      }
    } finally {
      _resumeTimelineRefreshRunning = false;
      if (_resumeTimelineRefreshRequested && _matrix.isLogged()) {
        unawaited(_refreshTimelineAfterResume());
      }
    }
  }

  Future<void> _hydrateCurrentTimeline(
    Timeline timeline,
    int generation,
  ) async {
    if (!_isCurrentTimeline(timeline, generation)) return;
    _timelineHydrationRequested = true;
    if (_timelineHydrationRunning) return;
    _timelineHydrationRunning = true;
    try {
      while (_timelineHydrationRequested) {
        _timelineHydrationRequested = false;
        final currentTimeline = _timeline;
        final currentGeneration = _timelineGeneration;
        if (currentTimeline == null ||
            !_isCurrentTimeline(currentTimeline, currentGeneration)) {
          continue;
        }
        final metadataTimer = Stopwatch()..start();
        await _hydrateTimelineMetadata(currentTimeline);
        if (!_isCurrentTimeline(currentTimeline, currentGeneration)) continue;
        _roomMessageCache[currentTimeline.room.id] = List.unmodifiable(
          _mappedMessages,
        );
        _debugRoomOpenTiming(
          'metadata_ms=${metadataTimer.elapsedMilliseconds} '
          'events=${currentTimeline.events.length}',
        );
      }
    } finally {
      _timelineHydrationRunning = false;
      // A timeline update can race the final loop condition. Reschedule rather
      // than allowing two hydration passes to overlap network and cache work.
      if (_timelineHydrationRequested && _timeline != null) {
        unawaited(_hydrateCurrentTimeline(_timeline!, _timelineGeneration));
      }
    }
  }

  Future<void> _markSelectedRoomRead() async {
    if (!_preferences.sendReadReceipts || !_mayAdvanceReadMarker) return;
    final initialTimeline = _timeline;
    if (initialTimeline == null || initialTimeline.room.id != _selectedRoomId) {
      return;
    }
    final roomId = initialTimeline.room.id;
    if (_roomsMarkingRead.contains(roomId)) return;
    _roomsMarkingRead.add(roomId);
    try {
      while (identical(initialTimeline, _timeline) &&
          roomId == _selectedRoomId &&
          _mayAdvanceReadMarker) {
        String? newestSyncedEventId;
        for (final event in initialTimeline.events) {
          if (event.status.isSynced &&
              event.relationshipType != RelationshipTypes.thread) {
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
        final hasThreads = initialTimeline.events.any(
          (event) => event.relationshipType == RelationshipTypes.thread,
        );
        if (hasThreads) {
          await _matrix.postReceipt(
            roomId,
            ReceiptType.mReadPrivate,
            newestSyncedEventId,
            threadId: 'main',
          );
          await _matrix.postReceipt(
            roomId,
            ReceiptType.mRead,
            newestSyncedEventId,
            threadId: 'main',
          );
        } else {
          await initialTimeline.setReadMarker(
            eventId: newestSyncedEventId,
            public: true,
          );
        }
        _lastMarkedReadEventIds[roomId] = newestSyncedEventId;
      }
    } catch (_) {
      // Receipt failures are non-fatal and will be retried on the next update.
    } finally {
      _roomsMarkingRead.remove(roomId);
    }
  }
}
