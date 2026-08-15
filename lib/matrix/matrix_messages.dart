part of 'matrix_backend.dart';

extension _MatrixMessages on MatrixBackend {
  Future<List<ChatMessage>> _searchRoomHistory(String query) async {
    final normalized = query.trim();
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (normalized.isEmpty || room == null) return const [];
    final roomId = room.id;
    try {
      final result = await room.searchEvents(
        searchTerm: normalized,
        limit: max(100, _preferences.timelineChunkSize),
      );
      if (_selectedRoomId != roomId) return const [];
      return result.events
          .where((event) => event.type == EventTypes.Message)
          .map(_searchResultFromEvent)
          .toList(growable: false);
    } catch (exception) {
      if (_selectedRoomId == roomId) {
        _error = _friendlyError(exception);
        _notifyBackendListeners();
      }
      rethrow;
    }
  }

  ChatMessage _searchResultFromEvent(Event event) => ChatMessage(
    id: event.eventId,
    sender: event.senderFromMemoryOrFallback.calcDisplayname(),
    senderId: event.senderId,
    body: event.calcUnlocalizedBody(
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
    ),
    timestamp: event.originServerTs,
    pending: false,
    own: event.senderId == _matrix.userID,
    avatarBytes: _senderAvatarBytes[event.senderId],
  );

  Future<void> _loadMoreHistory() async {
    final timeline = _timeline;
    if (timeline == null || _historyLoading || !timeline.canRequestHistory) {
      return;
    }
    _historyLoading = true;
    _notifyBackendListeners();
    try {
      await timeline.requestHistory(
        historyCount: _preferences.timelineChunkSize,
      );
      if (!identical(timeline, _timeline)) return;
      final hardCap = min(
        120,
        _preferences.timelineChunkSize * _preferences.timelineChunkCap,
      );
      if (timeline.events.length > hardCap) {
        timeline.events.removeRange(0, timeline.events.length - hardCap);
      }
      await _decryptTimelineEvents(timeline);
      if (!identical(timeline, _timeline)) return;
      await _hydrateTimelineMetadata(timeline);
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _historyLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _sendMessage(
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
          // Deltiecord does not expose the SDK's slash-command interface.
          // Treat Unix paths and other leading-slash text literally.
          parseCommands: false,
          // Rich markup is serialized by the composer and uses the branch
          // below; avoid a second, behaviorally different Markdown pass.
          parseMarkdown: false,
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
      _notifyBackendListeners();
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

  Future<void> _redactMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null) throw StateError('That message is no longer available.');
    if (!event.canRedact) throw StateError('You cannot delete that message.');
    try {
      await event.redactEvent(redactAllEdits: true);
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
    await event.cancelSend();
    _notifyBackendListeners();
  }

  Future<void> _toggleReaction(String messageId, String key) async {
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
      _notifyBackendListeners();
      rethrow;
    }
  }
}
