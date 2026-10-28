part of 'matrix_backend.dart';

extension _MatrixHistoryDownload on MatrixBackend {
  /// Direct pagination never changes the active timeline or read markers and
  /// does not bulk-store events/media in the SDK database.
  Future<HistoryDownloadPage> _downloadIndexPage(
    Client client,
    String roomId,
    String? cursor,
    bool Function() active,
    Set<String> attemptedBackup, {
    List<MatrixEvent>? suppliedEvents,
  }) async {
    final room = client.getRoomById(roomId);
    if (!active() ||
        !identical(client, _client) ||
        room == null ||
        room.isSpace ||
        _historyIndex?.scope.includes(_historyRoomKind(room)) != true ||
        room.membership != Membership.join) {
      throw StateError('The chat is no longer available.');
    }
    final response = suppliedEvents == null
        ? await client
              .getRoomEvents(
                roomId,
                Direction.b,
                from: cursor,
                limit: 100,
                filter: jsonEncode({
                  'types': [
                    EventTypes.Message,
                    EventTypes.Encrypted,
                    'm.sticker',
                    PollEventContent.startType,
                    'm.room.redaction',
                  ],
                }),
              )
              .timeout(const Duration(seconds: 30))
        : GetRoomEventsResponse(start: 'retry', chunk: suppliedEvents);
    if (!active() ||
        !identical(client, _client) ||
        room.membership != Membership.join) {
      throw StateError('Session changed.');
    }
    if (response.chunk.length > 200) {
      throw StateError('History page is too large.');
    }
    await _loadDownloadKeys(
      client,
      room,
      response.chunk,
      active,
      attemptedBackup,
    );
    final rows = <String, Map<String, Object?>>{};
    final failures = <HistoryDecryptionFailure>[];
    var unavailable = 0;
    for (var offset = 0; offset < response.chunk.length; offset += 4) {
      final events = await Future.wait(
        response.chunk.skip(offset).take(4).map((raw) async {
          var event = Event.fromMatrixEvent(raw, room);
          void failed() => failures.add(
            HistoryDecryptionFailure(
              roomId: roomId,
              eventId: event.eventId,
              senderId: event.senderId,
              timestamp: event.originServerTs.millisecondsSinceEpoch,
            ),
          );
          if (event.type == EventTypes.Encrypted && client.encryption != null) {
            try {
              event = await client.encryption!
                  .decryptRoomEvent(event, store: false)
                  .timeout(const Duration(seconds: 5));
            } catch (_) {
              failed();
              return null;
            }
          }
          if (event.type == EventTypes.Encrypted) {
            failed();
            return null;
          }
          return event;
        }),
      );
      if (!active() ||
          !identical(client, _client) ||
          room.membership != Membership.join) {
        throw StateError('Session changed.');
      }
      for (var event in events) {
        if (!active() ||
            !identical(client, _client) ||
            room.membership != Membership.join) {
          throw StateError('History download paused.');
        }
        if (event == null) {
          unavailable++;
          continue;
        }
        if (event.type == 'm.room.redaction') {
          final id = event.toJson()['redacts'] ?? event.content['redacts'];
          if (id is String) {
            rows[id] = {
              'id': id,
              'room': roomId,
              'time': 0,
              'kind': '',
              'deleted': true,
            };
          }
          continue;
        }
        if (event.type != EventTypes.Message &&
            event.type != 'm.sticker' &&
            event.type != PollEventContent.startType) {
          continue;
        }
        String? revision;
        var editedAt = 0;
        if (event.relationshipType == RelationshipTypes.edit) {
          final originalId = event.relationshipEventId;
          final replacement = event.content['m.new_content'];
          if (originalId == null || replacement is! Map) continue;
          final original = Event.fromMatrixEvent(
            await client
                .getOneRoomEvent(roomId, originalId)
                .timeout(const Duration(seconds: 15)),
            room,
          );
          if (!active() || !identical(client, _client)) {
            throw StateError('History download paused.');
          }
          if (original.redacted) {
            rows[originalId] = {
              'id': originalId,
              'room': roomId,
              'time': 0,
              'kind': '',
              'deleted': true,
            };
            continue;
          }
          if (original.senderId != event.senderId ||
              !{
                EventTypes.Message,
                EventTypes.Encrypted,
              }.contains(original.type)) {
            continue;
          }
          revision = event.eventId;
          editedAt = event.originServerTs.millisecondsSinceEpoch;
          event = Event.fromJson({
            ...original.toJson(),
            'type': EventTypes.Message,
            'content': replacement,
          }, room);
        }
        final kind = event.type == 'm.sticker'
            ? 'image'
            : switch (event.messageType) {
                'm.image' => 'image',
                'm.video' => 'video',
                'm.audio' => 'audio',
                'm.file' => 'file',
                _ =>
                  hasMessageWebLink(
                        event.body,
                        event.isRichMessage ? event.formattedText : null,
                      )
                      ? 'link'
                      : '',
              };
        var body = event.body;
        if (event.type == PollEventContent.startType && !event.redacted) {
          try {
            final poll = event.parsedPollEventContent.pollStartContent;
            body = [
              poll.question.mText,
              ...poll.answers.map((answer) => answer.mText),
            ].join('\n');
          } catch (_) {
            continue;
          }
        }
        final row = <String, Object?>{
          'id': event.eventId,
          'room': roomId,
          'time': event.originServerTs.millisecondsSinceEpoch,
          'sender': event.senderId,
          'kind': kind,
          'body': body,
          'revision': revision,
          'edited_at': editedAt,
          'deleted': event.redacted,
        };
        final previous = rows[event.eventId];
        if (row['deleted'] != true &&
            (previous?['deleted'] == true ||
                (previous?['edited_at'] as int? ?? 0) > editedAt)) {
          continue;
        }
        rows[event.eventId] = row;
      }
      await Future<void>.delayed(Duration.zero);
    }
    return HistoryDownloadPage(
      rows: rows.values.toList(),
      nextCursor: response.end,
      checked: response.chunk.length,
      unavailable: unavailable,
      failures: failures,
    );
  }

  Future<void> _loadDownloadKeys(
    Client client,
    Room room,
    Iterable<MatrixEvent> events,
    bool Function() active,
    Set<String> attempted,
  ) async {
    final sessions = <String>{
      for (final event in events)
        if (event.type == EventTypes.Encrypted)
          if (event.content['session_id'] case final String id)
            if (id.length <= 512) id,
    }.toList();
    final manager = client.encryption?.keyManager;
    if (sessions.isEmpty ||
        manager == null ||
        !manager.enabled ||
        !await manager.isCached()) {
      return;
    }
    for (var offset = 0; offset < sessions.length; offset += 4) {
      if (!active() || !identical(client, _client)) {
        throw StateError('History download paused.');
      }
      await Future.wait(
        sessions.skip(offset).take(4).map((session) async {
          if (await manager.loadInboundGroupSession(room.id, session) != null) {
            return;
          }
          final key = '${room.id}|$session';
          if (attempted.contains(key) || !active()) return;
          if (attempted.length >= 4096) attempted.remove(attempted.first);
          attempted.add(key);
          try {
            await manager
                .loadSingleKey(room.id, session)
                .timeout(const Duration(seconds: 10));
          } on MatrixException catch (error) {
            if (error.error != MatrixError.M_NOT_FOUND) rethrow;
          }
        }),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }
}
