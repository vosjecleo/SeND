part of 'matrix_backend.dart';

class _ReplyHydrationJob {
  Future<void>? running;
  Timer? retry;
  StreamSubscription<String>? keys;
  final missingSessions = <String>{};
  int retries = 0;
  bool requested = false;

  void dispose() {
    retry?.cancel();
    unawaited(keys?.cancel());
  }
}

/// Decrypts timeline events and progressively hydrates optional metadata.
///
/// Text is published before avatars, replies, and previews. Hydration passes
/// are serialized because sync bursts can otherwise duplicate network work and
/// let stale room results outlive a fast room switch.
extension _MatrixTimelineSupport on MatrixBackend {
  // Flutter's lazy sliver materializes only visible rows. Keep stable event
  // identities in that sliver instead of replacing both ends of a bounded UI
  // window; the latter made the scroll position irrecoverable after paging.
  List<Event> _timelineWindowEvents(Timeline timeline) {
    final segment = _timelineSegments.forTimeline(timeline);
    if (segment == null) return timeline.events;
    _timelineSegments.refreshKnown(segment);
    return segment.events;
  }

  void _onTimelineSegmentsChanged() {
    final active = _timelineSegments.active;
    final encrypted =
        active?.events
            .where((e) => e.type == EventTypes.Encrypted)
            .map((e) => e.eventId)
            .toList() ??
        <String>[];
    if (active != null &&
        (!identical(_timeline, active.timeline) ||
            encrypted.any((id) => !_segmentDecryptSeen.contains(id)))) {
      _timeline = active.timeline;
      _segmentDecryptSeen.addAll(encrypted);
      final timeline = active.timeline;
      final generation = _timelineGeneration;
      final lease = _sessionScope.capture();
      unawaited(() async {
        try {
          await _loadRoomBackupKeys(timeline.room, timeline);
          if (!lease.isCurrent || !_isCurrentTimeline(timeline, generation)) {
            return;
          }
          await _decryptTimelineEvents(timeline);
          if (!lease.isCurrent || !_isCurrentTimeline(timeline, generation)) {
            return;
          }
          await _hydrateCurrentTimeline(timeline, generation);
        } catch (_) {
          // Key recovery and media hydration remain retryable. Retain the
          // existing events and their SDK decryption status on failure.
        }
      }());
    }
    _notifyBackendListeners();
  }

  Future<void> _hydrateSenderAvatars(Timeline timeline) async {
    final lease = _sessionScope.capture();
    final client = timeline.room.client;
    bool current() => lease.isCurrent && identical(client, _client);
    final missing = <(String, Uri)>[];
    final seen = <String>{};
    for (final event in _timelineWindowEvents(timeline)) {
      if (!current()) return;
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
        _senderAvatarBytes[event.senderId] = bytes;
        continue;
      }
      final pooled =
          _avatarMediaPool.peek(avatar, AvatarMediaPool.profileDimension) ??
          _avatarMediaPool.peek(avatar, AvatarMediaPool.rowDimension);
      if (pooled != null) {
        _senderAvatarBytes[event.senderId] = pooled;
        continue;
      }
      missing.add((event.senderId, avatar));
    }

    for (var start = 0; start < missing.length; start += 4) {
      if (!current()) return;
      final end = min(start + 4, missing.length);
      await Future.wait(
        missing.sublist(start, end).map((entry) async {
          try {
            final bytes = await _avatarMedia(
              entry.$2,
              AvatarMediaPool.rowDimension,
            );
            if (current() &&
                bytes != null &&
                _senderAvatarUris[entry.$1] == entry.$2) {
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

  void _cancelReplyHydration([Timeline? timeline]) {
    if (timeline != null) {
      _replyHydrationJobs.remove(timeline)?.dispose();
      return;
    }
    for (final job in _replyHydrationJobs.values) {
      job.dispose();
    }
    _replyHydrationJobs.clear();
  }

  void _retryPendingReplies() {
    for (final timeline in _replyHydrationJobs.keys.toList()) {
      unawaited(_hydrateReplies(timeline));
    }
  }

  Iterable<Event> _replySources(Timeline timeline) =>
      _timelineWindowEvents(timeline).where(
        (event) =>
            {
              EventTypes.Message,
              EventTypes.Sticker,
              PollEventContent.startType,
            }.contains(event.type) &&
            event.inReplyToEventId() != null,
      );

  Future<void> _hydrateReplies(
    Timeline timeline, {
    bool automaticRetry = false,
  }) {
    final lease = _sessionScope.capture();
    final client = timeline.room.client;
    if (!lease.isCurrent || !identical(client, _client)) {
      return Future.value();
    }
    if (_replySources(timeline).isEmpty) {
      _cancelReplyHydration(timeline);
      return Future.value();
    }
    final job = _replyHydrationJobs.putIfAbsent(
      timeline,
      _ReplyHydrationJob.new,
    );
    bool current() =>
        lease.isCurrent &&
        identical(client, _client) &&
        identical(_replyHydrationJobs[timeline], job);
    job.retry?.cancel();
    job.retry = null;
    if (!automaticRetry) job.retries = 0;
    if (job.running case final work?) {
      job.requested = true;
      return work;
    }
    job.keys ??= timeline.room.onSessionKeyReceived.stream.listen((session) {
      if (current() && job.missingSessions.contains(session)) {
        unawaited(_hydrateReplies(timeline));
      }
    });
    final work = Future<void>.microtask(() async {
      do {
        job.requested = false;
        job.missingSessions.clear();
        await _hydrateRepliesPass(timeline, current, job.missingSessions.add);
      } while (current() && job.requested);
    });
    job.running = work;
    return work.whenComplete(() {
      job.running = null;
      if (!current()) return;
      final pending = _replySources(
        timeline,
      ).any((event) => !_replyPreviews.containsKey(event.eventId));
      if (!pending) {
        _cancelReplyHydration(timeline);
      } else if (job.retries < 3) {
        // Cover startup races without polling unavailable history forever.
        final delay = [1, 3, 10][job.retries++];
        job.retry = Timer(Duration(seconds: delay), () {
          if (current()) {
            unawaited(_hydrateReplies(timeline, automaticRetry: true));
          }
        });
      }
    });
  }

  Future<void> _hydrateRepliesPass(
    Timeline timeline,
    bool Function() current,
    void Function(String) missingSession,
  ) async {
    final client = timeline.room.client;
    final loaded = <String, Event>{
      for (final range in _timelineSegments.ranges)
        if (range.timeline.room.id == timeline.room.id)
          for (final event in range.events) event.eventId: event,
      for (final event in _timelineWindowEvents(timeline)) event.eventId: event,
    };
    final replies = _replySources(timeline).toList();
    final lookups = <String, Future<Event?>>{};
    Future<void> hydrate(Event event) async {
      if (!current()) return;
      final targetId = event.inReplyToEventId()!;
      var repliedTo = loaded[targetId];
      if (repliedTo == null && _replyPreviews.containsKey(event.eventId)) {
        return;
      }
      try {
        repliedTo ??= await lookups.putIfAbsent(
          targetId,
          () => event.getReplyEvent(timeline),
        );
        if (!current()) return;
        if (repliedTo == null) return;
        final sessionId = repliedTo.content['session_id'];
        if (repliedTo.type == EventTypes.Encrypted && sessionId is String) {
          missingSession(sessionId);
        }
        if (repliedTo.type == EventTypes.Encrypted &&
            client.encryption != null) {
          repliedTo = await client.encryption!.decryptRoomEvent(repliedTo);
        }
        if (!current()) return;
        if (!{
          EventTypes.Message,
          EventTypes.Sticker,
          PollEventContent.startType,
        }.contains(repliedTo.type)) {
          return;
        }
        // Keep the original event ID as the navigation target, but render its
        // latest replacement so reply previews cannot preserve a stale body.
        final originalEventId = repliedTo.eventId;
        final displayEvent = repliedTo.getDisplayEvent(timeline);
        final preview = ReplyPreview(
          eventId: originalEventId,
          senderId: displayEvent.senderId,
          sender: displayEvent.senderFromMemoryOrFallback.calcDisplayname(),
          body: displayEvent.calcUnlocalizedBody(
            hideReply: true,
            hideEdit: true,
            plaintextBody: true,
          ),
        );
        final old = _replyPreviews[event.eventId];
        if (old?.eventId != preview.eventId ||
            old?.senderId != preview.senderId ||
            old?.body != preview.body ||
            old?.sender != preview.sender) {
          _replyPreviews[event.eventId] = preview;
          _notifyBackendListeners();
          for (final session in _threadSessions) {
            if (identical(session._timeline, timeline)) {
              session._replyPreviewChanged();
            }
          }
        }
      } catch (_) {
        /* Keep this relation visible; retry on the next hydration. */
      }
    }

    // Cached originals should not sit behind an unrelated network lookup.
    final ordered = [
      ...replies.where((e) => loaded.containsKey(e.inReplyToEventId())),
      ...replies.where((e) => !loaded.containsKey(e.inReplyToEventId())),
    ];
    for (var start = 0; start < ordered.length; start += 4) {
      if (!current()) return;
      await Future.wait(ordered.skip(start).take(4).map(hydrate));
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
      final pending = List<Event>.of(timeline.events);
      var positions = {
        for (final (i, event) in timeline.events.indexed) event.eventId: i,
      };
      for (final event in pending) {
        if (event.type != EventTypes.Encrypted) continue;
        final decrypted = await encryption.decryptRoomEvent(
          event,
          store: true,
          updateType: EventUpdateType.history,
        );
        var index = positions[event.eventId];
        if (index == null ||
            index >= timeline.events.length ||
            timeline.events[index].eventId != event.eventId) {
          positions = {
            for (final (i, event) in timeline.events.indexed) event.eventId: i,
          };
          index = positions[event.eventId];
        }
        // Paging or live sync may move a row while decryption is awaiting a
        // session. Never write its plaintext into a different event's slot.
        if (index != null &&
            timeline.events[index].type == EventTypes.Encrypted &&
            !timeline.events[index].redacted) {
          timeline.events[index] = decrypted;
        }
      }
    });
    _notifyBackendListeners();
  }

  Future<void> _hydrateTimelineMetadata(Timeline timeline) async {
    final retainedEventIds = _timelineWindowEvents(
      timeline,
    ).map((event) => event.eventId).toSet();
    retainedEventIds.addAll(_forumRoots.keys);
    for (final session in _threadSessions) {
      retainedEventIds.addAll(
        session._timeline?.events.map((event) => event.eventId) ??
            const <String>[],
      );
    }
    final replyEventIds = {
      ...retainedEventIds,
      for (final range in _timelineSegments.ranges)
        for (final event in range.events) event.eventId,
    };
    _replyPreviews.removeWhere(
      (eventId, _) => !replyEventIds.contains(eventId),
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
      _hydrateLinkPreviews(timeline),
    ]);
    if (!identical(timeline, _timeline)) return;
    _notifyBackendListeners();
  }

  Future<void> _hydratePollResponses(Timeline timeline) async {
    final lease = _sessionScope.capture();
    final pending = timeline.events.where(
      (event) =>
          event.type == PollEventContent.startType &&
          !_hydratedPollResponseIds.contains(event.eventId),
    );
    for (final event in pending) {
      if (!lease.isCurrent) return;
      try {
        await event.fetchPollResponses(timeline);
        if (!lease.isCurrent) return;
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
    // Previously permissive sessions may already be known to unsigned devices.
    // Rotate before sending; keep historical inbound keys and backups intact.
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
      unawaited(_indexEvents(timeline.events).catchError((Object _) {}));
      _notifyBackendListeners();
      unawaited(_hydrateCurrentTimeline(timeline, generation));
      unawaited(_markSelectedRoomRead());
    }
  }

  Future<void> _refreshTimelineAfterResume() async {
    // Lifecycle/view focus can arrive while the protected database is opening.
    // Session initialization starts sync once a client actually exists.
    if (_client?.isLogged() != true) return;
    _notifyBackendListeners();
    if (_lastResumeTimelineRefresh != null &&
        DateTime.now().difference(_lastResumeTimelineRefresh!) <
            const Duration(seconds: 2)) {
      return;
    }
    _resumeTimelineRefreshRequested = true;
    if (_resumeTimelineRefreshRunning || _client?.isLogged() != true) return;
    _resumeTimelineRefreshRunning = true;
    try {
      while (_resumeTimelineRefreshRequested && _client?.isLogged() == true) {
        _resumeTimelineRefreshRequested = false;
        final timeline = _timeline;
        final generation = _timelineGeneration;
        try {
          // oneShotSync joins an outstanding long poll, even with timeout=0.
          // Invalidate that suspended request through the SDK before restarting;
          // abortSync waits for its database transaction and rejects stale data.
          // Keep the same Timeline, listeners, and scroll anchor throughout.
          final client = _client;
          if (client == null) return;
          // Focus can change several times while opening a desktop popup.
          // An actively processing sync must finish its transaction; don't
          // repeatedly abort and restart it for each focus event.
          await client.abortSync();
          if (!identical(client, _client) || !client.isLogged()) return;
          final refresh = client.oneShotSync(timeout: Duration.zero);
          client.backgroundSync = true;
          await refresh;
          _lastResumeTimelineRefresh = DateTime.now();
        } catch (_) {
          // The normal sync loop owns reconnect/backoff. A resume refresh is a
          // best-effort nudge and must never replace its connection state.
        }
        if (timeline != null && _isCurrentTimeline(timeline, generation)) {
          _onTimelineUpdate(generation);
        }
        if (timeline == null || _isCurrentTimeline(timeline, generation)) {
          _resumeTimelineRefreshRequested = false;
        }
      }
    } finally {
      _resumeTimelineRefreshRunning = false;
      if (_resumeTimelineRefreshRequested && _client?.isLogged() == true) {
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
    if (!_mayAdvanceReadMarker) return;
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
        for (final event in _timelineWindowEvents(initialTimeline)) {
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
        await acknowledgeRoom(
          initialTimeline.room,
          newestSyncedEventId,
          sendPublicReceipts: _preferences.sendReadReceipts,
          mainThreadOnly: hasThreads,
        );
        _lastMarkedReadEventIds[roomId] = newestSyncedEventId;
      }
    } catch (_) {
      // Receipt failures are non-fatal and will be retried on the next update.
    } finally {
      _roomsMarkingRead.remove(roomId);
    }
  }
}
