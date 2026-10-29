part of 'matrix_backend.dart';

extension _MatrixForumIndex on MatrixBackend {
  Future<void> _loadForumThreads({bool refresh = false}) async {
    final timeline = _timeline;
    if (timeline == null ||
        _presentationFor(timeline.room) != RoomPresentation.forum ||
        _forumLoading ||
        (!refresh && !_forumHasMore)) {
      return;
    }
    final generation = _timelineGeneration;
    _forumLoading = true;
    try {
      final page = await _matrix.getThreadRoots(
        timeline.room.id,
        limit: 30,
        from: refresh ? null : _forumCursor,
      );
      final roots = <Event>[];
      for (final raw in page.chunk) {
        var event = Event.fromMatrixEvent(raw, timeline.room);
        if (event.type == EventTypes.Encrypted && _matrix.encryption != null) {
          event = await _matrix.encryption!.decryptRoomEvent(event);
        }
        roots.add(event);
      }
      if (!_isCurrentTimeline(timeline, generation)) return;
      for (final root in roots) {
        _forumRoots[root.eventId] = root;
      }
      _forumHasMore = page.nextBatch != null && page.nextBatch != _forumCursor;
      _forumCursor = page.nextBatch;
      _notifyBackendListeners();
    } on MatrixException catch (error) {
      if (error.error != MatrixError.M_UNRECOGNIZED &&
          error.error != MatrixError.M_NOT_FOUND) {
        rethrow;
      }
      if (_isCurrentTimeline(timeline, generation)) _forumHasMore = false;
      // Older homeservers still expose ordinary post history via /messages.
    } finally {
      if (_isCurrentTimeline(timeline, generation)) _forumLoading = false;
    }
  }
}

class _MatrixThreadSession extends ThreadSession {
  _MatrixThreadSession(this.backend, this.room, this.rootId)
    : client = room.client,
      lease = backend._sessionScope.capture();

  final MatrixBackend backend;
  final Room room;
  final Client client;
  final SessionLease lease;
  bool get _active =>
      !_disposed && lease.isCurrent && identical(backend._client, client);
  @override
  ConversationSendTarget get sendTarget => ConversationSendTarget(
    roomId: roomId,
    threadRootId: rootId,
    sticker: (sticker) {
      if (!lease.isCurrent || !identical(backend._client, client)) {
        throw StateError('The account session has ended.');
      }
      return backend._sendSticker(
        sticker,
        roomId: roomId,
        threadRootEventId: rootId,
      );
    },
    send: (text, {formattedBody, editMessageId, replyToMessageId}) {
      if (!lease.isCurrent || !identical(backend._client, client)) {
        throw StateError('The account session has ended.');
      }
      return backend._sendMessage(
        text,
        roomId: roomId,
        formattedBody: formattedBody,
        editMessageId: editMessageId,
        replyToMessageId: replyToMessageId,
        threadRootEventId: editMessageId == rootId ? null : rootId,
      );
    },
    attach: (draft, {replyToMessageId}) {
      if (!lease.isCurrent || !identical(backend._client, client)) {
        throw StateError('The account session has ended.');
      }
      return backend._sendAttachment(
        draft,
        roomId: roomId,
        threadRootEventId: rootId,
        replyToMessageId: replyToMessageId,
      );
    },
  );
  @override
  final String rootId;
  Timeline? _timeline;
  String? _next;
  bool _disposed = false;
  bool _viewVisible = false;
  @override
  bool get visible => _active && _viewVisible;
  @override
  void setVisible(bool visible) {
    _viewVisible = visible;
  }

  bool _loading = false;
  bool _more = true;
  String? _error;
  String? _lastRead;
  bool _hydrating = false, _needsHydration = false;
  late final _cache = backend._threadHistoryFor(client);
  String get _cacheKey => '$roomId\u0000$rootId';
  Timer? _typingStop;
  DateTime? _lastTyping;
  @override
  List<String> get typingNames => !_active
      ? const []
      : room.typingUsers
            .where((user) => user.id != client.userID)
            .map((user) => user.calcDisplayname())
            .toList();
  @override
  Future<void> setTyping(bool typing) async {
    if (!_active || !backend.preferences.sendTypingNotifications) return;
    if (typing &&
        _lastTyping != null &&
        DateTime.now().difference(_lastTyping!) < const Duration(seconds: 3)) {
      return;
    }
    _typingStop?.cancel();
    _lastTyping = typing ? DateTime.now() : null;
    try {
      await room.setTyping(typing, timeout: 5000);
      if (typing && _active) {
        _typingStop = Timer(
          const Duration(seconds: 4),
          () => unawaited(setTyping(false)),
        );
      }
    } catch (_) {
      /* Typing must not interrupt editing while offline. */
    }
  }

  @override
  Future<void> sendSticker(StickerSummary sticker) {
    _requireAccount();
    return backend._sendSticker(
      sticker,
      roomId: roomId,
      threadRootEventId: rootId,
    );
  }

  @override
  Future<void> sendPoll(PollDraft poll) {
    _requireAccount();
    return backend._sendPoll(poll, roomId: roomId, threadRootEventId: rootId);
  }

  @override
  Future<void> schedule(String text, DateTime at, {String? replyToMessageId}) {
    _requireAccount();
    return backend._scheduleMessage(
      text,
      at,
      roomId: roomId,
      replyToMessageId: replyToMessageId,
      threadRootEventId: rootId,
    );
  }

  void _requireAccount() {
    if (!lease.isCurrent || !identical(backend._client, client)) {
      throw StateError('The account session has ended.');
    }
  }

  @override
  String get roomId => room.id;
  @override
  bool get loading => _loading;
  @override
  bool get canLoadMore => !_disposed && _more;
  @override
  String? get error => _error;
  @override
  List<ChatMessage> get messages {
    final timeline = _timeline;
    if (timeline == null || !_active) return const [];
    return backend.conversationMessages(
      roomId: roomId,
      threadRootId: rootId,
      sent: backend._mapTimelineEvents(
        timeline,
        timeline.events.where(
          (event) =>
              event.eventId == rootId ||
              (event.relationshipType == RelationshipTypes.thread &&
                  event.relationshipEventId == rootId),
        ),
      ),
    );
  }

  Future<void> initialize() async {
    final cached = <Event>[];
    final cachedRows = await _cache.get(_cacheKey);
    if (!_active) return;
    for (final row in cachedRows) {
      try {
        final event = Event.fromJson(Map<String, dynamic>.from(row), room);
        if (event.eventId == rootId ||
            (event.relationshipType == RelationshipTypes.thread &&
                event.relationshipEventId == rootId)) {
          cached.add(event);
        }
      } catch (_) {
        /* Ignore malformed optional cache rows, never live data. */
      }
    }
    final root =
        backend._eventById(rootId) ??
        cached.where((e) => e.eventId == rootId).firstOrNull ??
        await room.getEventById(rootId);
    if (!_active) return;
    if (root == null) throw StateError('This discussion is unavailable.');
    if (root.relationshipType == RelationshipTypes.thread) {
      throw StateError(
        'Open the original discussion rather than nesting a thread.',
      );
    }
    final timeline = await room.getTimeline(limit: 30, onUpdate: _changed);
    if (!_active) {
      timeline.cancelSubscriptions();
      return;
    }
    _timeline = timeline;
    backend.addListener(_backendChanged);
    // Room-wide limited-sync trimming must not discard a separately paged
    // discussion root/history. Live event and key subscriptions remain active.
    await timeline.roomSub?.cancel();
    final ids = timeline.events.map((e) => e.eventId).toSet();
    timeline.events.addAll(cached.where((e) => ids.add(e.eventId)));
    if (!timeline.events.any((event) => event.eventId == rootId)) {
      timeline.events.add(root);
    }
    timeline.events.sort(
      (a, b) => b.originServerTs.compareTo(a.originServerTs),
    );
    unawaited(loadMore());
  }

  void _backendChanged() {
    if (!_active) return;
    notifyListeners();
  }

  void _changed() {
    if (!_active) return;
    final timeline = _timeline;
    if (timeline != null) {
      timeline.events.removeWhere(
        (event) =>
            event.eventId != rootId &&
            !(event.relationshipType == RelationshipTypes.thread &&
                event.relationshipEventId == rootId),
      );
      final retained = timeline.events.map((event) => event.eventId).toSet();
      timeline.aggregatedEvents.removeWhere((id, _) => !retained.contains(id));
      _needsHydration = true;
      unawaited(_hydrate());
    }
    notifyListeners();
  }

  Future<void> _hydrate() async {
    if (_hydrating || !_active) return;
    _hydrating = true;
    try {
      while (_needsHydration && _active) {
        _needsHydration = false;
        final timeline = _timeline;
        if (timeline == null) return;
        try {
          await Future.wait([
            backend._hydrateSenderAvatars(timeline),
            backend._hydrateReplies(timeline),
            backend._hydratePollResponses(timeline),
            backend._hydrateLinkPreviews(timeline, isCurrent: () => _active),
          ]);
        } catch (_) {
          /* Text/history remain usable if optional metadata fails. */
        }
        if (_active) notifyListeners();
      }
    } finally {
      _hydrating = false;
    }
  }

  void _persistSnapshot() {
    final timeline = _timeline;
    if (!_active || timeline == null) return;
    final root = timeline.events.where((e) => e.eventId == rootId).firstOrNull;
    if (root == null) return;
    unawaited(
      _cache.put(_cacheKey, [
        root.toJson(),
        ...timeline.events
            .where((e) => e.eventId != rootId && e.status.isSynced)
            .take(89)
            .map((e) => e.toJson()),
      ]),
    );
  }

  @override
  Future<void> loadMore() async {
    final timeline = _timeline;
    if (!_active || _loading || !_more || timeline == null) return;
    _loading = true;
    _error = null;
    _changed();
    try {
      final page = await client.getRelatingEventsWithRelType(
        room.id,
        rootId,
        RelationshipTypes.thread,
        from: _next,
        limit: 30,
        dir: Direction.b,
      );
      final events = <Event>[];
      for (final raw in page.chunk) {
        if (!_active) return;
        var event = Event.fromMatrixEvent(raw, room);
        if (event.type == EventTypes.Encrypted && client.encryption != null) {
          event = await client.encryption!.decryptRoomEvent(event);
        }
        events.add(event);
      }
      if (!_active) return;
      final ids = timeline.events.map((event) => event.eventId).toSet();
      timeline.events.addAll(events.where((event) => ids.add(event.eventId)));
      timeline.events.sort(
        (a, b) => b.originServerTs.compareTo(a.originServerTs),
      );
      _more = page.nextBatch != null && page.nextBatch != _next;
      _next = page.nextBatch;
      _changed();
      await Future.wait([
        backend._hydrateSenderAvatars(timeline),
        backend._hydrateReplies(timeline),
      ]);
      if (_disposed) return;
      _changed();
      // Reuse the SDK's relation cache for historical edits and reactions.
      // This is bounded by this page and released with the discussion.
      for (var start = 0; start < events.length; start += 4) {
        if (_disposed) return;
        await Future.wait(
          events.skip(start).take(4).map((event) async {
            await timeline.fetchAggregatedEvents(
              event.eventId,
              RelationshipTypes.edit,
            );
            if (_disposed) return;
            await timeline.fetchAggregatedEvents(
              event.eventId,
              RelationshipTypes.reaction,
            );
          }),
        );
      }
    } catch (error) {
      if (!_disposed) _error = backend._friendlyError(error);
    } finally {
      _loading = false;
      _persistSnapshot();
      _changed();
    }
  }

  @override
  Future<void> send(
    String text, {
    String? formattedBody,
    String? editMessageId,
    String? replyToMessageId,
  }) {
    if (!_active) throw StateError('This discussion has been closed.');
    if (editMessageId != null &&
        !messages.any(
          (m) =>
              m.id == editMessageId &&
              m.own &&
              !m.redacted &&
              !m.pending &&
              !m.failed,
        )) {
      throw StateError(
        'Only your own messages in this discussion can be edited.',
      );
    }
    return backend._sendMessage(
      text,
      roomId: roomId,
      formattedBody: formattedBody,
      replyToMessageId: replyToMessageId,
      editMessageId: editMessageId,
      threadRootEventId:
          editMessageId == null ||
              backend._eventById(editMessageId)?.relationshipType ==
                  RelationshipTypes.thread
          ? rootId
          : null,
    );
  }

  @override
  Future<void> attach(AttachmentDraft attachment, {String? replyToMessageId}) {
    if (!_active) throw StateError('This discussion has been closed.');
    return backend._sendAttachment(
      attachment,
      roomId: roomId,
      threadRootEventId: rootId,
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<void> markRead(String eventId) async {
    if (!_active ||
        !_viewVisible ||
        !backend._applicationForeground ||
        backend._manualUnreadHolds.contains(roomId) ||
        eventId == _lastRead) {
      return;
    }
    if (!messages.any(
      (message) => message.id == eventId && !message.pending && !message.failed,
    )) {
      return;
    }
    _lastRead = eventId;
    try {
      await client.postReceipt(
        roomId,
        ReceiptType.mReadPrivate,
        eventId,
        threadId: rootId,
      );
      if (backend.preferences.sendReadReceipts && _active) {
        await client.postReceipt(
          roomId,
          ReceiptType.mRead,
          eventId,
          threadId: rootId,
        );
      }
    } catch (_) {
      if (_lastRead == eventId) _lastRead = null;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _persistSnapshot();
    _disposed = true;
    _typingStop?.cancel();
    if (_lastTyping != null &&
        lease.isCurrent &&
        identical(backend._client, client)) {
      unawaited(room.setTyping(false).catchError((Object _) {}));
    }
    backend.removeListener(_backendChanged);
    _timeline?.cancelSubscriptions();
    _timeline = null;
    backend._threadSessions.remove(this);
    super.dispose();
  }
}
