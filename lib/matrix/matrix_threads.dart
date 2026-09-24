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
  _MatrixThreadSession(this.backend, this.room, this.rootId);

  final MatrixBackend backend;
  final Room room;
  @override
  final String rootId;
  Timeline? _timeline;
  String? _next;
  bool _disposed = false;
  bool _loading = false;
  bool _more = true;
  String? _error;
  String? _lastRead;

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
    if (timeline == null || _disposed) return const [];
    return backend._mapTimelineEvents(
      timeline,
      timeline.events.where(
        (event) =>
            event.eventId == rootId ||
            (event.relationshipType == RelationshipTypes.thread &&
                event.relationshipEventId == rootId),
      ),
    );
  }

  Future<void> initialize() async {
    final root = await room.getEventById(rootId);
    if (root == null) throw StateError('This discussion is unavailable.');
    if (root.relationshipType == RelationshipTypes.thread) {
      throw StateError(
        'Open the original discussion rather than nesting a thread.',
      );
    }
    final timeline = await room.getTimeline(limit: 30, onUpdate: _changed);
    if (_disposed) {
      timeline.cancelSubscriptions();
      return;
    }
    _timeline = timeline;
    // Room-wide limited-sync trimming must not discard a separately paged
    // discussion root/history. Live event and key subscriptions remain active.
    await timeline.roomSub?.cancel();
    if (!timeline.events.any((event) => event.eventId == rootId)) {
      timeline.events.add(root);
    }
    unawaited(loadMore());
  }

  void _changed() {
    if (_disposed) return;
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
    }
    notifyListeners();
  }

  @override
  Future<void> loadMore() async {
    final timeline = _timeline;
    if (_disposed || _loading || !_more || timeline == null) return;
    _loading = true;
    _error = null;
    _changed();
    try {
      final page = await backend._matrix.getRelatingEventsWithRelType(
        room.id,
        rootId,
        RelationshipTypes.thread,
        from: _next,
        limit: 30,
        dir: Direction.b,
      );
      final events = <Event>[];
      for (final raw in page.chunk) {
        var event = Event.fromMatrixEvent(raw, room);
        if (event.type == EventTypes.Encrypted &&
            backend._matrix.encryption != null) {
          event = await backend._matrix.encryption!.decryptRoomEvent(event);
        }
        events.add(event);
      }
      if (_disposed) return;
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
      _changed();
    }
  }

  @override
  Future<void> send(
    String text, {
    String? formattedBody,
    String? editMessageId,
  }) {
    if (_disposed) throw StateError('This discussion has been closed.');
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
  Future<void> attach(AttachmentDraft attachment) {
    if (_disposed) throw StateError('This discussion has been closed.');
    return backend._sendAttachment(
      attachment,
      roomId: roomId,
      threadRootEventId: rootId,
    );
  }

  @override
  Future<void> markRead(String eventId) async {
    if (_disposed || !backend._applicationForeground || eventId == _lastRead) {
      return;
    }
    if (!messages.any(
      (message) => message.id == eventId && !message.pending && !message.failed,
    )) {
      return;
    }
    _lastRead = eventId;
    try {
      await backend._matrix.postReceipt(
        roomId,
        ReceiptType.mReadPrivate,
        eventId,
        threadId: rootId,
      );
      if (backend.preferences.sendReadReceipts && !_disposed) {
        await backend._matrix.postReceipt(
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
    _disposed = true;
    _timeline?.cancelSubscriptions();
    _timeline = null;
    backend._threadSessions.remove(this);
    super.dispose();
  }
}
