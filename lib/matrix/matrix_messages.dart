part of 'matrix_backend.dart';

extension _MatrixMessages on MatrixBackend {
  Future<List<ChatMessage>> _loadPinnedMessages() async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null || room.pinnedEventIds.isEmpty) return const [];
    final roomId = room.id;
    final results = <ChatMessage>[];
    for (final eventId in room.pinnedEventIds) {
      try {
        var event = await room.getEventById(eventId);
        if (_selectedRoomId != roomId) return const [];
        if (event == null) continue;
        if (event.type == EventTypes.Encrypted && _matrix.encryption != null) {
          event = await _matrix.encryption!.decryptRoomEvent(event);
        }
        if (event.type == EventTypes.Message) {
          results.add(_searchResultFromEvent(event));
        }
      } catch (_) {
        // A redacted or inaccessible pin must not prevent other pins loading.
      }
    }
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  Future<List<ChatMessage>> _searchRoomHistory(String query) async {
    final normalized = query.trim();
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (normalized.isEmpty || room == null) return const [];
    final roomId = room.id;
    final generation = ++_historySearchGeneration;
    if (_historySearchRoom != roomId || _historySearchQuery != normalized) {
      _historySearchRoom = roomId;
      _historySearchQuery = normalized;
      _historySearchCursor = null;
      _historySearchComplete = false;
      _historySearchMessages.clear();
      _indexSearchOffset = 0;
      _indexSearchDone = false;
    }
    final previousCursor = _historySearchCursor;
    try {
      final parsed = MessageSearchQuery.parse(normalized);
      final index = await openHistoryIndex();
      List<Event> page = const [];
      String? nextCursor = previousCursor;
      var networkPage = false;
      if (!_indexSearchDone &&
          index != null &&
          (index.enabled || parsed.terms.isEmpty)) {
        final ids = await index
            .query(
              roomId,
              terms: parsed.terms,
              kind: parsed.has,
              sender: parsed.from,
              before: parsed.before?.millisecondsSinceEpoch,
              after: parsed.after?.millisecondsSinceEpoch,
              offset: _indexSearchOffset,
            )
            .catchError((Object _) => <String>[]);
        _indexSearchOffset += ids.length;
        _indexSearchDone = ids.length < 50;
        page = await _historyEvents(room, ids);
      } else {
        _indexSearchDone = true;
      }
      if (page.isEmpty && !_historySearchComplete) {
        final result = await _historyPage(room, previousCursor);
        page = result.$1;
        nextCursor = result.$2;
        networkPage = true;
      }
      if (_selectedRoomId != roomId || generation != _historySearchGeneration) {
        return const [];
      }
      if (networkPage) {
        _historySearchCursor = nextCursor;
        _historySearchComplete =
            nextCursor == null || nextCursor == previousCursor;
      }
      final matches = <String, ChatMessage>{
        ..._historySearchMessages,
        for (final message in searchMessages(normalized)) message.id: message,
      };
      for (var event in page) {
        if (event.type == EventTypes.Encrypted && _matrix.encryption != null) {
          try {
            event = await _matrix.encryption!.decryptRoomEvent(event);
          } catch (_) {
            continue;
          }
        }
        if (event.type != EventTypes.Message) continue;
        final message = _searchResultFromEvent(event);
        if (!matchesMessageSearch(
          body: message.body,
          sender: message.sender,
          query: normalized,
          senderId: message.senderId,
          roomName: room.getLocalizedDisplayname(),
          timestamp: message.timestamp,
          attachment: message.attachment,
        )) {
          continue;
        }
        matches[message.id] = message;
      }
      if (_selectedRoomId != roomId || generation != _historySearchGeneration) {
        return const [];
      }
      final sorted = matches.values.toList(growable: false)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _historySearchMessages
        ..clear()
        ..addAll(matches);
      return sorted;
    } catch (exception) {
      if (_selectedRoomId == roomId) {
        _error = _friendlyError(exception);
        _notifyBackendListeners();
      }
      rethrow;
    }
  }

  Future<Event?> _historyEvent(Room room, String id) async {
    try {
      var event = _attachmentEvents[id] ?? await room.getEventById(id);
      if (event?.type == EventTypes.Encrypted && _matrix.encryption != null) {
        event = await _matrix.encryption!.decryptRoomEvent(
          event!,
          store: false,
        );
      }
      return event?.type == EventTypes.Message && event?.redacted != true
          ? await _applyIndexedRevision(room, event!)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Event>> _historyEvents(Room room, List<String> ids) async {
    final events = <Event>[];
    for (var i = 0; i < ids.length; i += 6) {
      if (!identical(room.client, _client)) return const [];
      events.addAll(
        (await Future.wait(
          ids
              .skip(i)
              .take(6)
              .map(
                (id) => _historyEvent(
                  room,
                  id,
                ).timeout(const Duration(seconds: 8), onTimeout: () => null),
              ),
        )).whereType<Event>(),
      );
    }
    return events;
  }

  Future<Event> _applyIndexedRevision(Room room, Event event) async {
    final revision = await _historyIndex
        ?.revision(event.eventId)
        .catchError((Object _) => null);
    if (!event.redacted && revision != null) {
      final edit = await room.getEventById(revision);
      if (edit != null &&
          !edit.redacted &&
          edit.senderId == event.senderId &&
          edit.relationshipEventId == event.eventId &&
          edit.content['m.new_content'] is Map) {
        return Event.fromJson({
          ...event.toJson(),
          'content': edit.content['m.new_content'],
        }, room);
      }
    }
    return event;
  }

  Future<(List<Event>, String?)> _historyPage(Room room, String? cursor) async {
    final client = room.client;
    final response = await client.getRoomEvents(
      room.id,
      Direction.b,
      from: cursor,
      limit: 100,
      filter: jsonEncode({
        'types': [EventTypes.Message, EventTypes.Encrypted, 'm.room.redaction'],
      }),
    );
    if (!identical(client, _client)) return (<Event>[], null);
    final events = <Event>[];
    // Bound decryption concurrency; a missing session must not stall every
    // following event in the page or monopolize the UI isolate.
    for (var i = 0; i < response.chunk.length; i += 4) {
      final batch = await Future.wait(
        response.chunk.skip(i).take(4).map((raw) async {
          var event = Event.fromMatrixEvent(raw, room);
          if (event.type == EventTypes.Encrypted && client.encryption != null) {
            try {
              event = await client.encryption!
                  .decryptRoomEvent(event, store: false)
                  .timeout(const Duration(seconds: 5));
            } catch (_) {
              return null;
            }
          }
          return event;
        }),
      );
      events.addAll(batch.whereType<Event>());
      await Future<void>.delayed(Duration.zero);
    }
    await _indexEvents(events).catchError((Object _) {});
    return (
      events
          .where(
            (e) =>
                e.type == EventTypes.Message &&
                !e.redacted &&
                e.relationshipType != RelationshipTypes.edit,
          )
          .toList(),
      response.end,
    );
  }

  Future<void> _indexEvents(Iterable<Event> events) async {
    final list = events.toList();
    if (list.isEmpty || !identical(list.first.room.client, _client)) return;
    final index = await openHistoryIndex();
    if (index == null || !identical(list.first.room.client, _client)) return;
    final rows = <Map<String, Object?>>[];
    for (var event in list) {
      if (!event.status.isSent) continue;
      final fingerprint = jsonEncode([
        event.content,
        event.redacted,
        index.enabled,
      ]).hashCode;
      if (_indexFingerprints[event.eventId] == fingerprint) continue;
      _indexFingerprints[event.eventId] = fingerprint;
      while (_indexFingerprints.length > 4000) {
        _indexFingerprints.remove(_indexFingerprints.keys.first);
      }
      if (event.type == 'm.room.redaction') {
        final id = event.toJson()['redacts'] ?? event.content['redacts'];
        if (id is String) {
          rows.add({
            'id': id,
            'room': event.room.id,
            'time': 0,
            'kind': '',
            'deleted': true,
          });
          _mediaHistory[event.room.id]?.remove(id);
          _attachmentEvents.remove(id);
        }
        continue;
      }
      if (event.type != EventTypes.Message) continue;
      if (!index.enabled &&
          !event.hasAttachment &&
          event.relationshipType != RelationshipTypes.edit &&
          !event.redacted &&
          !RegExp(r'https?://', caseSensitive: false).hasMatch(event.body)) {
        continue;
      }
      String? revision;
      var editedAt = 0;
      if (event.relationshipType == RelationshipTypes.edit) {
        revision = event.eventId;
        editedAt = event.originServerTs.millisecondsSinceEpoch;
        final original = await event.room.getEventById(
          event.relationshipEventId!,
        );
        if (original == null ||
            original.senderId != event.senderId ||
            event.content['m.new_content'] is! Map) {
          continue;
        }
        event = Event.fromJson({
          ...original.toJson(),
          'content': event.content['m.new_content'],
        }, event.room);
      }
      final message = _searchResultFromEvent(event);
      rows.add({
        'id': event.eventId,
        'room': event.room.id,
        'time': event.originServerTs.millisecondsSinceEpoch,
        'sender': event.senderId,
        'kind':
            message.attachment?.kind.name ??
            (RegExp(r'https?://', caseSensitive: false).hasMatch(message.body)
                ? 'link'
                : ''),
        'body': index.enabled ? message.body : '',
        'revision': revision,
        'edited_at': editedAt,
        'deleted': event.redacted,
      });
      if (event.redacted) _mediaHistory[event.room.id]?.remove(event.eventId);
    }
    if (rows.isNotEmpty) {
      try {
        await index.ingest(rows);
      } catch (_) {
        for (final row in rows) {
          _indexFingerprints.remove(row['id']);
        }
        rethrow;
      }
    }
  }

  Future<List<ChatMessage>> _loadMediaPage(String roomId) async {
    final room = _client?.getRoomById(roomId);
    if (room == null || _mediaEnded.contains(roomId)) {
      return mediaMessagesForRoom(roomId);
    }
    final index = await openHistoryIndex();
    final records = _mediaHistory.putIfAbsent(roomId, () => {});
    final offset = _mediaIndexOffset[roomId] ?? 0;
    if (index != null && offset >= 0) {
      final ids = await index
          .query(roomId, kind: 'media', offset: offset)
          .catchError((Object _) => <String>[]);
      _mediaIndexOffset[roomId] = ids.length < 50 ? -1 : offset + ids.length;
      for (final event in await _historyEvents(room, ids)) {
        records[event.eventId] = _searchResultFromEvent(event);
      }
      if (ids.isNotEmpty) {
        _notifyBackendListeners();
        return mediaMessagesForRoom(roomId);
      }
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final previous = _mediaCursor[roomId];
      final page = await _historyPage(room, previous);
      if (!identical(room.client, _client)) return const [];
      final before = records.length;
      for (final event in page.$1) {
        final message = _searchResultFromEvent(event);
        if (message.attachment?.kind == AttachmentKind.image ||
            message.attachment?.kind == AttachmentKind.video) {
          records[event.eventId] = message;
        }
      }
      _mediaCursor[roomId] = page.$2;
      if (page.$2 == null || page.$2 == previous) _mediaEnded.add(roomId);
      if (records.length > before || _mediaEnded.contains(roomId)) break;
    }
    // Keep room metadata caches separate from image/video byte caches.
    while (_mediaHistory.length > 4) {
      final old = _mediaHistory.keys.firstWhere((id) => id != roomId);
      _mediaHistory.remove(old);
      _mediaCursor.remove(old);
      _mediaEnded.remove(old);
      _mediaIndexOffset.remove(old);
    }
    _notifyBackendListeners();
    return mediaMessagesForRoom(roomId);
  }

  ChatMessage _searchResultFromEvent(Event event) {
    _indexedEventRooms[event.eventId] = event.room.id;
    while (_indexedEventRooms.length > 12000) {
      _indexedEventRooms.remove(_indexedEventRooms.keys.first);
    }
    final attachment = _attachmentFor(event);
    return ChatMessage(
      id: event.eventId,
      sender: event.senderFromMemoryOrFallback.calcDisplayname(),
      senderId: event.senderId,
      body:
          attachment?.caption ??
          (attachment == null
              ? event.calcUnlocalizedBody(
                  hideReply: true,
                  hideEdit: true,
                  plaintextBody: true,
                )
              : ''),
      timestamp: event.originServerTs,
      pending: false,
      own: event.senderId == _matrix.userID,
      avatarBytes: _senderAvatarBytes[event.senderId],
      attachment: attachment,
    );
  }

  Future<void> _loadMoreHistory({String? anchorEventId}) async {
    final timeline = _timeline;
    if (timeline == null || _historyLoading || !canLoadMoreHistory) {
      return;
    }
    _historyLoading = true;
    _notifyBackendListeners();
    try {
      final pageSize = _preferences.timelineChunkSize;
      var loaded = 0;
      var visibleLoaded = 0;
      // Relations, edits, and malformed events do not become visible rows. A
      // single raw 30-event page can therefore yield far fewer than 30 chat
      // rows. Continue through a bounded number of raw pages so opening a room
      // does not immediately strand the user behind another pagination click.
      for (
        var pass = 0;
        pass < 8 && visibleLoaded < pageSize && canLoadMoreHistory;
        pass++
      ) {
        final beforeIds = timeline.events.map((event) => event.eventId).toSet();
        var pageLoaded = 0;
        if (!_timelineDatabaseExhausted) {
          pageLoaded = await _appendStoredHistory(timeline, pageSize);
        }
        if (pageLoaded == 0 && _timelineDatabaseExhausted) {
          pageLoaded = await _appendServerHistory(timeline, pageSize);
        }
        loaded += pageLoaded;
        if (!identical(timeline, _timeline)) return;
        visibleLoaded += timeline.events.where((event) {
          return !beforeIds.contains(event.eventId) &&
              _isVisibleTimelineEvent(event) &&
              _isPersonallyVisibleEvent(event) &&
              event.relationshipType != RelationshipTypes.edit;
        }).length;
        if (pageLoaded == 0 && !canLoadMoreHistory) break;
      }
      if (!identical(timeline, _timeline)) return;
      if (loaded == 0) return;
      await _decryptTimelineEvents(timeline);
      if (!identical(timeline, _timeline)) return;
      unawaited(_hydrateCurrentTimeline(timeline, _timelineGeneration));
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _historyLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<int> _appendStoredHistory(Timeline timeline, int pageSize) async {
    var added = 0;
    final knownEventIds = timeline.events.map((event) => event.eventId).toSet();
    while (added < pageSize && !_timelineDatabaseExhausted) {
      final requested = pageSize - added;
      final stored = await _matrix.database.getEventList(
        timeline.room,
        start: _timelineDatabaseOffset,
        limit: requested,
      );
      _timelineDatabaseOffset = TimelineWindowPolicy.advanceDatabaseOffset(
        _timelineDatabaseOffset,
        stored.length,
      );
      if (stored.length < requested) _timelineDatabaseExhausted = true;
      if (stored.isEmpty) break;
      for (final event in stored) {
        if (!knownEventIds.add(event.eventId)) continue;
        timeline.addAggregatedEvent(event);
        timeline.events.add(event);
        added++;
      }
    }
    return added;
  }

  Future<int> _appendServerHistory(Timeline timeline, int pageSize) async {
    if (timeline.chunk.prevBatch.isEmpty) {
      timeline.chunk.prevBatch = timeline.room.prev_batch ?? '';
    }
    if (timeline.chunk.prevBatch.isEmpty) {
      _timelineServerExhausted = true;
      return 0;
    }
    // Once local history is consumed, paginate with the chunk token directly.
    // SeND's separate database cursor may have consumed local rows even
    // when the SDK timeline still has a usable server continuation token.
    timeline.isFragmentedTimeline = true;
    final beforeIds = timeline.events.map((event) => event.eventId).toSet();
    final previousToken = timeline.chunk.prevBatch;
    await timeline.getRoomEvents(
      historyCount: pageSize,
      direction: Direction.b,
    );
    TimelineWindowPolicy.deduplicateBy(
      timeline.events,
      (event) => event.eventId,
    );
    final loaded = timeline.events
        .where((event) => !beforeIds.contains(event.eventId))
        .length;
    if (timeline.chunk.prevBatch.isEmpty ||
        timeline.chunk.prevBatch == previousToken) {
      _timelineServerExhausted = true;
    }
    return loaded;
  }

  Future<void> _loadMoreFuture({String? anchorEventId}) async {
    final timeline = _timeline;
    if (timeline == null || _historyLoading || !timeline.canRequestFuture) {
      return;
    }
    _historyLoading = true;
    _notifyBackendListeners();
    try {
      if (timeline.canRequestFuture) {
        await timeline.requestFuture(
          historyCount: _preferences.timelineChunkSize,
        );
      }
      if (!identical(timeline, _timeline)) return;
      TimelineWindowPolicy.deduplicateBy(
        timeline.events,
        (event) => event.eventId,
      );
      await _decryptTimelineEvents(timeline);
      if (!identical(timeline, _timeline)) return;
      unawaited(_hydrateCurrentTimeline(timeline, _timelineGeneration));
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _historyLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _sendMessage(
    String text, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
    String? threadRootEventId,
  }) async {
    final originalValue = text.trim();
    final value = _preferences.improveTwitterLinks
        ? rewriteTwitterLinks(originalValue)
        : originalValue;
    final targetRoomId = roomId ?? _selectedRoomId;
    if (value.isEmpty || targetRoomId == null) return;
    try {
      final room = _matrix.getRoomById(targetRoomId);
      if (room == null) throw StateError('The selected room is unavailable.');
      await _prepareEncryptedSend(room);
      final transactionId = _matrix.generateUniqueTransactionId();
      final replyEvent = replyToMessageId == null
          ? null
          : _eventById(replyToMessageId);
      late Future<String?> operation;
      final outgoingFormattedBody =
          formattedBody != null && _preferences.improveTwitterLinks
          ? rewriteTwitterLinks(formattedBody)
          : formattedBody;
      final mentions = _mentionsFor(value, replyEvent, room);
      if ((outgoingFormattedBody == null || outgoingFormattedBody.isEmpty) &&
          mentions.isEmpty) {
        operation = room.sendTextEvent(
          value,
          threadRootEventId: threadRootEventId,
          threadLastEventId: threadRootEventId,
          txid: transactionId,
          inReplyTo: replyEvent,
          editEventId: editMessageId,
          // SeND does not expose the SDK's slash-command interface.
          // Treat Unix paths and other leading-slash text literally.
          parseCommands: false,
          // Rich markup is serialized by the composer and uses the branch
          // below; avoid a second, behaviorally different Markdown pass.
          parseMarkdown: false,
        );
      } else {
        operation = room.sendEvent(
          {
            'msgtype': MessageTypes.Text,
            'body': value,
            'format': 'org.matrix.custom.html',
            if (outgoingFormattedBody?.isNotEmpty == true) ...{
              'format': 'org.matrix.custom.html',
              'formatted_body': outgoingFormattedBody,
            },
            ...mentions,
          },
          inReplyTo: replyEvent,
          threadRootEventId: threadRootEventId,
          threadLastEventId: threadRootEventId,
          editEventId: editMessageId,
          txid: transactionId,
        );
      }
      operation = operation.then((id) {
        // Track acknowledged sends, never draft taps, local echoes or edits.
        if (id != null && editMessageId == null) {
          unawaited(
            FavouriteReactionsStore.instance
                .recordSentMessage(value, outgoingFormattedBody)
                .catchError((Object _) {}),
          );
        }
        return id;
      });
      if (_connectionStatus != ConnectionStatus.online) {
        _offlineSendRooms[transactionId] = room.id;
        _notifyBackendListeners();
        unawaited(_completeOfflineSend(transactionId, room.id, operation));
        return;
      }
      final eventId = await operation;
      if (eventId == null && _connectionStatus != ConnectionStatus.online) {
        _offlineSendRooms[transactionId] = room.id;
        _notifyBackendListeners();
      }
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _completeOfflineSend(
    String transactionId,
    String roomId,
    Future<String?> operation,
  ) async {
    if (_offlineSendRooms[transactionId] != roomId) return;
    try {
      final eventId = await operation;
      if (eventId != null) _offlineSendRooms.remove(transactionId);
    } catch (exception) {
      if (_connectionStatus == ConnectionStatus.online) {
        _offlineSendRooms.remove(transactionId);
        _error = _friendlyError(exception);
      }
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _retryOfflineSends() async {
    if (_retryingOfflineSends || _offlineSendRooms.isEmpty) return;
    _retryingOfflineSends = true;
    try {
      for (final entry in Map.of(_offlineSendRooms).entries) {
        if (_connectionStatus != ConnectionStatus.online) break;
        final room = _matrix.getRoomById(entry.value);
        if (room == null) {
          _offlineSendRooms.remove(entry.key);
          continue;
        }
        Event? event;
        try {
          event = await _matrix.database.getEventById(entry.key, room);
        } catch (_) {
          event = null;
        }
        if (event == null || event.status.isSent) {
          _offlineSendRooms.remove(entry.key);
          continue;
        }
        if (!event.status.isError) continue;
        try {
          final eventId = await event.sendAgain(txid: entry.key);
          if (eventId != null) _offlineSendRooms.remove(entry.key);
        } catch (_) {
          if (_connectionStatus == ConnectionStatus.online) {
            // A connected failure is authoritative (for example forbidden).
            _offlineSendRooms.remove(entry.key);
          }
        }
      }
    } finally {
      _retryingOfflineSends = false;
      _notifyBackendListeners();
    }
  }

  Map<String, Object> _mentionsFor(String text, Event? replyEvent, Room room) {
    final userIds = RegExp(r'@[A-Za-z0-9._=\-/]+:[^\s<>()]+')
        .allMatches(text)
        .map((match) => match.group(0)!)
        .where((userId) => userId != _matrix.userID)
        .toSet();
    final roles = _rolesForRoom(room);
    final joined = room
        .getParticipants()
        .where((member) => member.membership == Membership.join)
        .map((member) => member.id)
        .toSet();
    userIds.addAll(
      roles.mentionedMembers(text, joined, exclude: _matrix.userID),
    );
    if (replyEvent != null && replyEvent.senderId != _matrix.userID) {
      userIds.add(replyEvent.senderId);
    }
    final everyone = containsRoomMention(text);
    if (RegExp(r'(^|\s)@all(?=\s|$)').hasMatch(text)) {
      for (final member in room.getParticipants()) {
        // ignore: deprecated_member_use
        if (_matrix.presences[member.id]?.presence == PresenceType.online &&
            member.id != _matrix.userID) {
          userIds.add(member.id);
        }
      }
    }
    if (userIds.isEmpty && !everyone) return const {};
    return {
      'm.mentions': {
        if (userIds.isNotEmpty) 'user_ids': userIds.toList(growable: false),
        if (everyone) 'room': true,
      },
    };
  }

  Event? _eventById(String eventId) {
    if (_forumRoots.containsKey(eventId)) return _forumRoots[eventId];
    for (final session in _threadSessions) {
      for (final event in session._timeline?.events ?? <Event>[]) {
        if (event.eventId == eventId) return event;
      }
    }
    final timeline = _timeline;
    if (timeline == null) return null;
    for (final event in timeline.events) {
      if (event.eventId == eventId) return event;
    }
    return null;
  }

  Future<void> _redactMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null) throw StateError('That message is no longer available.');
    if (!event.canRedact) throw StateError('You cannot delete that message.');
    try {
      await event.redactEvent(redactAllEdits: true);
      // Indexed roots outside the live timeline do not receive its in-place
      // redaction updates. Drop the cached copy once the server accepts it.
      if (_forumRoots.remove(messageId) != null) _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _retryMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || !event.status.isError) {
      throw StateError('That failed message is no longer available.');
    }
    try {
      _dismissedLocalEchoIds.remove(messageId);
      await _prepareEncryptedSend(event.room);
      await event.sendAgain();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _cancelPendingMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || event.status.isSent) return;
    // `cancelSend` removes the SDK's database row, but some failure paths keep
    // the in-memory local echo in the current Timeline. Hide it immediately
    // and forget its offline-send ownership so a permanently failed echo can
    // never reappear or be retried after the user explicitly discards it.
    _dismissedLocalEchoIds.add(messageId);
    _offlineSendRooms.remove(messageId);
    _notifyBackendListeners();
    try {
      await event.cancelSend();
    } catch (_) {
      // A missing SDK row is already the desired durable result. The local
      // suppression remains authoritative for the lifetime of this timeline.
    }
    _cacheCurrentRoomMessages();
    _notifyBackendListeners();
  }

  Future<void> _toggleReaction(
    String messageId,
    String key, {
    CustomEmojiReference? customEmoji,
  }) async {
    final value = (customEmoji?.id.toString() ?? key).trim();
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
        if (customEmoji == null) {
          await event.room.sendReaction(event.eventId, value);
        } else {
          await event.room.sendEvent({
            'm.relates_to': {
              'rel_type': RelationshipTypes.reaction,
              'event_id': event.eventId,
              'key': value,
            },
            // Matrix's annotation key remains the immutable MXC ID. This
            // namespaced fallback keeps deleted/renamed emoji intelligible.
            'net.deltiecord.emoji': {
              'id': customEmoji.id.toString(),
              'name': customEmoji.name,
              if (customEmoji.packId != null) 'pack': customEmoji.packId,
            },
          }, type: EventTypes.Reaction);
        }
      }
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }
}
