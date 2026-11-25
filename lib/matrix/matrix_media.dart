part of 'matrix_backend.dart';

extension _MatrixMedia on MatrixBackend {
  Uri? _storageMediaUri(Map<String, dynamic> file) {
    final id = file['media_id'];
    final raw = file['mxc'];
    final mxc = raw is String ? Uri.tryParse(raw) : null;
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,255}$').hasMatch(id) ||
        mxc == null ||
        mxc.scheme != 'mxc' ||
        mxc.pathSegments.length != 1 ||
        mxc.pathSegments.single != id ||
        mxc.host.isEmpty ||
        mxc.userInfo.isNotEmpty ||
        mxc.hasQuery ||
        mxc.hasFragment) {
      return null;
    }
    return mxc;
  }

  String? _storageEventMediaUrl(Event event) =>
      event.redacted ||
          !event.hasAttachment ||
          (event.messageType != MessageTypes.Image &&
              event.messageType != MessageTypes.Video)
      ? null
      : event.content
                .tryGetMap<String, Object?>('file')
                ?.tryGet<String>('url') ??
            event.content.tryGet<String>('url');

  Future<Map<String, ChatMessage>> _serverStorageAttachments(
    List<Map<String, dynamic>> files, {
    required bool Function() isCurrent,
  }) async {
    final client = _client;
    if (client == null || !isCurrent()) return {};
    final lease = _sessionScope.capture();
    bool current() =>
        isCurrent() && lease.isCurrent && identical(client, _client);
    final pending = <String, Map<String, dynamic>>{
      for (final file in files.take(100))
        if (_storageMediaUri(file) case final uri?) uri.toString(): file,
    };
    final result = <String, ChatMessage>{};
    void match(Event event) {
      if (!identical(event.room.client, client) ||
          event.room.membership != Membership.join) {
        return;
      }
      final file = pending.remove(_storageEventMediaUrl(event));
      if (file != null) {
        result[file['media_id'] as String] = _searchResultFromEvent(event);
      }
    }

    for (final event in List<Event>.of(_attachmentEvents.values)) {
      match(event);
    }
    // One bounded scan per selection screen, not one per tile. Use only the
    // local timeline and local keys; the search does not fetch room history
    // from the homeserver or request missing encryption keys.
    final rooms = _joinedRooms.where((room) => !room.isSpace).toList()
      ..sort((a, b) {
        if (a.id == _selectedRoomId) return b.id == _selectedRoomId ? 0 : -1;
        if (b.id == _selectedRoomId) return 1;
        return (b.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0)
            .compareTo(a.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0);
      });
    final encryption = client.encryption;
    final exhausted = <String>{};
    final checkedKeys = <(String, String)>{};
    var decryptions = 0;
    for (var offset = 0; offset < 128 && pending.isNotEmpty; offset += 32) {
      for (final room in rooms.take(32)) {
        if (!current()) return {};
        if (pending.isEmpty) break;
        if (exhausted.contains(room.id)) continue;
        try {
          final events = await client.database.getEventList(
            room,
            start: offset,
            limit: 32,
          );
          if (!current()) return {};
          if (events.length < 32) exhausted.add(room.id);
          for (var event in events.take(32)) {
            if (!current()) return {};
            if (pending.isEmpty) break;
            if (event.senderId != client.userID || event.redacted) continue;
            if (event.type == EventTypes.Encrypted &&
                encryption != null &&
                decryptions < 256) {
              decryptions++;
              try {
                final session = event.parsedRoomEncryptedContent.sessionId;
                if (session == null) continue;
                final keys = encryption.keyManager;
                if (keys.getInboundGroupSession(room.id, session)?.isValid !=
                        true &&
                    checkedKeys.add((room.id, session))) {
                  await keys.loadInboundGroupSession(room.id, session);
                }
                if (!current()) return {};
                event = encryption.decryptRoomEventSync(event);
              } catch (_) {
                continue;
              }
            }
            match(event);
          }
        } catch (_) {
          exhausted.add(room.id);
        }
      }
    }
    if (!current()) return {};
    for (final file in pending.values) {
      final message = _storageClearAttachment(file, _storageMediaUri(file)!);
      if (message != null) result[file['media_id'] as String] = message;
    }
    return result;
  }

  Future<ChatMessage?> _serverStorageAttachment(
    Map<String, dynamic> file,
  ) async {
    final mxc = _storageMediaUri(file);
    if (mxc == null || _client == null) return null;
    for (final event in List<Event>.of(_attachmentEvents.values)) {
      if (identical(event.room.client, _client) &&
          event.room.membership == Membership.join &&
          _storageEventMediaUrl(event) == mxc.toString()) {
        return _searchResultFromEvent(event);
      }
    }
    return _storageClearAttachment(file, mxc);
  }

  ChatMessage? _storageClearAttachment(Map<String, dynamic> file, Uri mxc) {
    final id = mxc.pathSegments.single;
    final mime = file['mimetype'] as String? ?? '';
    if (!mime.startsWith('image/') && !mime.startsWith('video/')) return null;
    // An encrypted blob cannot be viewed without its message's descriptor.
    final room = Room(id: '!storage-preview:local', client: _matrix);
    final event = Event.fromJson({
      'event_id': 'storage:$id',
      'sender': _matrix.userID,
      'origin_server_ts': file['created_ts'] ?? 0,
      'type': EventTypes.Message,
      'content': {
        'msgtype': mime.startsWith('video/')
            ? MessageTypes.Video
            : MessageTypes.Image,
        'body': 'Upload',
        'url': mxc.toString(),
        'info': {'mimetype': mime, 'size': file['bytes']},
      },
    }, room);
    return ChatMessage(
      id: event.eventId,
      sender: 'Upload',
      body: '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        file['created_ts'] as int? ?? 0,
      ),
      pending: false,
      attachment: _attachmentFor(event),
    );
  }

  Future<Uint8List?> _loadAttachmentPreview(
    String messageId, {
    bool Function()? requestCurrent,
  }) async {
    if (requestCurrent?.call() == false) return null;
    final lease = _sessionScope.capture();
    final client = _client;
    final generation = _attachmentCacheGeneration;
    final event = await _resolveAttachmentEvent(messageId);
    if (event == null ||
        !event.hasAttachment ||
        event.redacted ||
        !lease.isCurrent ||
        !identical(client, _client) ||
        !identical(event.room.client, client) ||
        generation != _attachmentCacheGeneration ||
        requestCurrent?.call() == false) {
      return null;
    }
    bool current() =>
        lease.isCurrent &&
        identical(client, _client) &&
        generation == _attachmentCacheGeneration &&
        requestCurrent?.call() != false;
    final cached =
        _attachmentBytesCache['${event.eventId}:thumbnail'] ??
        _attachmentBytesCache['${event.eventId}:grid-preview'] ??
        (event.messageType == MessageTypes.Image
            ? _attachmentBytesCache['${event.eventId}:original']
            : null);
    if (cached != null) {
      await BoundedMatrixMedia.checkImage(cached);
      return current() ? cached : null;
    }
    Uint8List? bytes;
    if (event.hasThumbnail) {
      try {
        final file = await BoundedMatrixMedia.attachment(
          event,
          thumbnail: true,
          maximumBytes: 2 * 1024 * 1024,
          isCurrent: current,
        );
        bytes = file.bytes;
      } catch (_) {
        if (!current()) return null;
      }
    }
    if (bytes == null &&
        event.messageType == MessageTypes.Image &&
        !event.content.containsKey('file')) {
      final uri = Uri.tryParse(event.content['url'] as String? ?? '');
      if (uri?.isScheme('mxc') == true) {
        // Prefer the small server thumbnail where encryption permits it.
        try {
          bytes = await BoundedMatrixMedia.image(
            event.room.client,
            uri!,
            width: 256,
            height: 256,
            crop: false,
            animated: false,
            maximumBytes: 2 * 1024 * 1024,
            isCurrent: current,
          );
        } catch (_) {
          if (!current()) return null;
        }
      }
    }
    if (bytes == null && event.messageType == MessageTypes.Image && current()) {
      // Legacy encrypted images often have no thumbnail at all. Browsing a
      // visible tile may fetch a bounded original, not history indexing.
      final file = await BoundedMatrixMedia.attachment(
        event,
        maximumBytes: BoundedMatrixMedia.inlineBytes,
        isCurrent: current,
      );
      if (!current()) return null;
      bytes = await BoundedMatrixMedia.run(() => imageGridPreview(file.bytes));
    }
    if (bytes == null || !current()) return null;
    final dimensions = await readEncodedImageDimensions(
      bytes,
      maximumPixels: 8000000,
      maximumFramePixels: 32000000,
    );
    if (dimensions == null || !current()) return null;
    _cacheMediaBytes('${event.eventId}:grid-preview', bytes);
    return bytes;
  }

  Future<Uint8List> _loadSavedGifPreview(SavedGifReference reference) async {
    final client = _matrix;
    final lease = _sessionScope.capture();
    final room = client.getRoomById(reference.roomId);
    if (room == null || room.membership != Membership.join) {
      throw StateError('The original GIF is unavailable.');
    }
    var event = _currentAttachmentEvent(reference.eventId);
    if (event?.room.id != room.id) event = null;
    event ??= await room.getEventById(reference.eventId);
    if (event?.type == EventTypes.Encrypted && client.encryption != null) {
      event = await client.encryption!.decryptRoomEvent(event!);
    }
    if (event == null ||
        event.redacted ||
        !event.hasAttachment ||
        event.messageType != MessageTypes.Image ||
        (!_isAnimatedImageMime(event.attachmentMimetype) &&
            event.content['net.send.animated'] != true) ||
        !lease.isCurrent ||
        !identical(client, _client)) {
      throw StateError('The original GIF is unavailable.');
    }
    final file = await BoundedMatrixMedia.attachment(
      event,
      maximumBytes: 25 * 1024 * 1024,
      isCurrent: () => lease.isCurrent && identical(client, _client),
    );
    return file.bytes;
  }

  void _rememberUploadedAttachment(String eventId, AttachmentDraft draft) {
    if (draft.mimeType.startsWith('image/')) {
      _cacheMediaBytes('$eventId:original', draft.bytes);
    }
    if (draft.videoThumbnail case final thumbnail?) {
      _cacheMediaBytes('$eventId:thumbnail', thumbnail);
    }
  }

  void _cacheMediaBytes(String key, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) return;
    _attachmentBytesCacheSize -= _attachmentBytesCache.remove(key)?.length ?? 0;
    _attachmentBytesCache[key] = bytes;
    _attachmentBytesCacheSize += bytes.length;
    while (_attachmentBytesCache.length >
            MatrixBackend._maximumCachedAttachments ||
        _attachmentBytesCacheSize >
            MatrixBackend._maximumCachedAttachmentBytes) {
      final removed = _attachmentBytesCache.remove(
        _attachmentBytesCache.keys.first,
      );
      _attachmentBytesCacheSize -= removed?.length ?? 0;
    }
  }

  Future<Event?> _resolveAttachmentEvent(String id) async {
    final cached = _currentAttachmentEvent(id);
    if (cached != null) return cached;
    final room = _client?.getRoomById(roomIdForMessage(id) ?? '');
    if (room == null) return null;
    final event = await _historyEvent(room, id);
    if (event != null) _attachmentFor(event);
    return event;
  }

  Event? _currentAttachmentEvent(String messageId) {
    final event = _eventById(messageId) ?? _attachmentEvents[messageId];
    if (event == null) return null;
    for (final timeline in [
      _timeline,
      ..._threadSessions.map((session) => session._timeline),
    ]) {
      if (timeline != null && timeline.room.id == event.room.id) {
        final displayed = event.getDisplayEvent(timeline);
        if (displayed.eventId != event.eventId) return displayed;
      }
    }
    return event;
  }

  String? _getAttachmentReference(String messageId) {
    final event = _currentAttachmentEvent(messageId);
    if (event == null || !event.hasAttachment) return null;
    final encryptedReference = event.content
        .tryGetMap<String, Object?>('file')
        ?.tryGet<String>('url');
    final reference = encryptedReference ?? event.content.tryGet<String>('url');
    final uri = Uri.tryParse(reference ?? '');
    // Only expose the stable MXC identifier. Download URLs can contain a
    // homeserver access token, and encrypted file metadata contains the key.
    return uri?.isScheme('mxc') == true ? uri.toString() : null;
  }

  Future<void> _refreshStorageUsage() async {
    _storageLoading = true;
    _notifyBackendListeners();
    try {
      final directory = await getDeltiecordDataDirectory();
      var total = 0;
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) total += await entity.length();
        }
      }
      _storageUsageBytes = total;
    } finally {
      _storageLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _clearMediaCache() async {
    for (final source in _mediaPlaybackSources.values) {
      releaseBrowserMediaUrl(source.uri);
    }
    _mediaPlaybackSources.clear();
    _mediaPlaybackReferences.clear();
    _mediaRangeProxy.clear();
    _attachmentBytesCache.clear();
    _attachmentDownloads.clear();
    _attachmentBytesCacheSize = 0;
    _attachmentCacheGeneration++;
    _linkPreviews.clear();
    _avatarBytes.clear();
    _notificationAvatarBytes.clear();
    _senderAvatarBytes.clear();
    await _avatarMediaPool.clear();
    _notifyBackendListeners();
    await _refreshStorageUsage();
  }

  Future<void> _sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
    String? threadRootEventId,
    String? editMessageId,
    Map<String, dynamic>? additionalContent,
  }) async {
    final room = _matrix.getRoomById(roomId ?? _selectedRoomId ?? '');
    if (room == null) throw StateError('The selected room is unavailable.');
    final account = _personal;
    try {
      attachment = assignMediaGallery([attachment]).single;
      attachment = await prepareImage(
        attachment,
        _preferences.imageCompression,
      );
      if (_preferences.optimizeVideos && !attachment.videoPrepared) {
        attachment = await VideoPreparation.instance.prepare(
          attachment,
          preset: _preferences.videoCompression,
        );
      } else {
        attachment = await VideoPreparation.probe(attachment);
      }
      if (attachment.bytes.length > attachmentUploadBudget) {
        throw AttachmentBudgetExceeded([attachment]);
      }
      await _validateUploadSize(attachment.bytes.length);
      final rawImage = isRawImageFile(attachment.name, attachment.mimeType);
      final animatedImage =
          !rawImage &&
          attachment.mimeType.startsWith('image/') &&
          hasAnimatedImageHeader(attachment.bytes);
      // Standard Matrix info travels with the (encrypted) event, so receivers
      // can lay out images before downloading them, including animated GIFs.
      final imageDimensions =
          !rawImage && attachment.mimeType.startsWith('image/')
          ? await readEncodedImageDimensions(attachment.bytes)
          : null;
      final posterDimensions = attachment.videoThumbnail == null
          ? null
          : await readEncodedImageDimensions(attachment.videoThumbnail!);
      await _prepareEncryptedSend(room);
      final replyEvent = replyToMessageId == null
          ? null
          : _eventById(replyToMessageId);
      // MatrixFile still derives m.image from the GIF MIME type, while
      // deliberately avoiding MatrixImageFile's synchronous GIF decode and
      // thumbnail generation on Flutter's UI isolate.
      final file = rawImage
          ? RawImageMatrixFile(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
            )
          : attachment.mimeType.startsWith('video/') &&
                attachment.videoWidth != null
          ? MatrixVideoFile(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
              width: attachment.videoWidth,
              height: attachment.videoHeight,
              duration: attachment.durationMilliseconds,
            )
          : attachment.mimeType == 'image/gif'
          ? SizedMatrixFile(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
              width: imageDimensions?.width,
              height: imageDimensions?.height,
            )
          : imageDimensions != null
          ? MatrixImageFile(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
              width: imageDimensions.width,
              height: imageDimensions.height,
            )
          : MatrixFile.fromMimeType(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
            );
      final transactionId =
          queuedTransactionId ?? _matrix.generateUniqueTransactionId();
      final operation = attachment.voiceMessage
          ? room.sendFileEvent(
              MatrixAudioFile(
                bytes: attachment.bytes,
                name: attachment.name,
                mimeType: attachment.mimeType,
                duration: attachment.durationMilliseconds,
              ),
              threadRootEventId: threadRootEventId,
              threadLastEventId: threadRootEventId,
              txid: transactionId,
              inReplyTo: replyEvent,
              // sendAudioEvent in our SDK adds the waveform but not the voice
              // marker. Other clients need both to distinguish a recording
              // from a generic audio upload. Encryption stays in the SDK.
              extraContent: {
                ...?additionalContent,
                'org.matrix.msc3245.voice': <String, Object?>{},
                'org.matrix.msc1767.audio': {
                  'duration': attachment.durationMilliseconds,
                  'waveform': attachment.waveform,
                },
              },
            )
          : room.sendFileEvent(
              file,
              editEventId: editMessageId,
              thumbnail: attachment.videoThumbnail == null
                  ? null
                  : MatrixImageFile(
                      bytes: attachment.videoThumbnail!,
                      name: 'thumbnail.jpg',
                      mimeType: 'image/jpeg',
                      width: posterDimensions?.width,
                      height: posterDimensions?.height,
                    ),
              threadRootEventId: threadRootEventId,
              threadLastEventId: threadRootEventId,
              txid: transactionId,
              inReplyTo: replyEvent,
              // Re-encoding large images here is CPU-heavy and stalls Flutter's UI
              // isolate. The SDK still generates a thumbnail, but uploads the
              // original image without a redundant full-resolution shrink pass.
              shrinkImageMaxDimension: null,
              extraContent:
                  additionalContent != null ||
                      animatedImage ||
                      attachment.spoiler ||
                      attachment.gallery != null ||
                      attachment.gifSource != null ||
                      replyEvent != null ||
                      attachment.caption?.trim().isNotEmpty == true
                  ? {
                      ...?additionalContent,
                      if (attachment.gallery case final gallery?)
                        MediaGalleryMembership.contentKey: gallery.toJson(),
                      if (animatedImage) 'net.send.animated': true,
                      ..._mentionsFor(
                        attachment.caption ?? '',
                        replyEvent,
                        room,
                      ),
                      if (attachment.gifSource != null)
                        'net.deltiecord.gif_source': attachment.gifSource
                            .toString(),
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
      if (_connectionStatus != ConnectionStatus.online) {
        _offlineSendRooms[transactionId] = room.id;
        _notifyBackendListeners();
        unawaited(_completeOfflineSend(transactionId, room.id, operation));
        return;
      }
      final eventId = await operation;
      if (eventId != null &&
          attachment.gifSource != null &&
          identical(account, _personal)) {
        // Account data contains a reference only, never attachment keys.
        try {
          await account?.set(
            'gif.upload:${attachment.gifSource}',
            SavedGifReference(roomId: room.id, eventId: eventId).toJson(),
          );
        } catch (_) {
          /* Sending succeeded; remembering reuse is best effort. */
        }
      }
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

  Future<Uint8List> _downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async {
    final event = await _resolveAttachmentEvent(messageId);
    if (event == null || !event.hasAttachment) {
      throw StateError('That attachment is no longer available.');
    }
    final cacheKey = '${event.eventId}:${thumbnail ? 'thumbnail' : 'original'}';
    final cached = _attachmentBytesCache.remove(cacheKey);
    if (cached != null) {
      _attachmentBytesCache[cacheKey] = cached;
      return cached;
    }
    final pending = _attachmentDownloads[cacheKey];
    if (pending != null) return pending;
    final operation = _downloadAndCacheAttachment(
      cacheKey,
      event,
      thumbnail: thumbnail,
      generation: _attachmentCacheGeneration,
    );
    _attachmentDownloads[cacheKey] = operation;
    return operation.whenComplete(() {
      if (identical(_attachmentDownloads[cacheKey], operation)) {
        _attachmentDownloads.remove(cacheKey);
      }
    });
  }

  Future<Uint8List> _downloadAndCacheAttachment(
    String cacheKey,
    Event event, {
    required bool thumbnail,
    required int generation,
  }) async {
    final file = await BoundedMatrixMedia.attachment(
      event,
      thumbnail: thumbnail && event.hasThumbnail,
      isCurrent: () => generation == _attachmentCacheGeneration,
      maximumBytes:
          thumbnail ||
              event.type == EventTypes.Sticker ||
              event.messageType == MessageTypes.Image ||
              event.attachmentMimetype.startsWith('image/')
          ? BoundedMatrixMedia.inlineBytes
          : BoundedMatrixMedia.fileBytes,
    );
    final bytes = file.bytes;
    // Cache only bounded media. This avoids repeatedly downloading/decrypting
    // GIFs as virtualized rows leave and re-enter the viewport without turning
    // a single huge attachment into permanent process memory.
    if (generation == _attachmentCacheGeneration) {
      _cacheMediaBytes(cacheKey, bytes);
    }
    return bytes;
  }

  Future<MediaPlaybackSource?> _getMediaPlaybackSource(String messageId) async {
    final event = await _resolveAttachmentEvent(messageId);
    if (event == null || !event.hasAttachment) {
      return null;
    }
    final cached = _mediaPlaybackSources[messageId];
    if (cached != null &&
        (kIsWeb ||
            cached.uri.host != '127.0.0.1' ||
            _mediaRangeProxy.contains(cached.uri))) {
      _mediaPlaybackReferences.update(messageId, (value) => value + 1);
      return _preparePlaybackSource(messageId, cached);
    }
    if (cached != null) {
      _mediaPlaybackSources.remove(messageId);
    }
    if (kIsWeb) {
      if (_matrix.contentScannerConfig != null) {
        throw StateError(
          'Bounded video loading is unavailable with this scanner.',
        );
      }
      // Browser video elements cannot attach Authorization headers or use the
      // native loopback range proxy. Keep this fallback explicitly bounded.
      final size = event.infoMap.tryGet<int>('size');
      if (size == null || size <= 0 || size > 64 * 1024 * 1024) {
        throw StateError(
          'Browser playback supports videos up to 64 MiB with known size. Download this video or send an optimized copy from the native app.',
        );
      }
      final file = await event.downloadAndDecryptAttachment(
        downloadCallback: (uri) {
          if (uri.scheme != 'https' ||
              uri.origin != _matrix.homeserver?.origin) {
            throw StateError(
              'Browser playback requires media served by your homeserver.',
            );
          }
          return downloadBrowserMedia(
            uri,
            _matrix.accessToken ?? '',
            64 * 1024 * 1024,
          );
        },
      );
      final bytes = file.bytes;
      if (bytes.length > 64 * 1024 * 1024) {
        throw StateError('Video exceeds the browser playback limit.');
      }
      final source = MediaPlaybackSource(
        uri: createBrowserMediaUrl(bytes, event.attachmentMimetype),
        headers: const {},
      );
      _mediaPlaybackSources[messageId] = source;
      _mediaPlaybackReferences[messageId] =
          (_mediaPlaybackReferences[messageId] ?? 0) + 1;
      return source;
    }
    if (event.isAttachmentEncrypted) {
      final file = event.content.tryGetMap<String, Object?>('file');
      final mxc = Uri.tryParse(file?.tryGet<String>('url') ?? '');
      final keyText = file
          ?.tryGetMap<String, Object?>('key')
          ?.tryGet<String>('k');
      final ivText = file?.tryGet<String>('iv');
      final hashText = file
          ?.tryGetMap<String, Object?>('hashes')
          ?.tryGet<String>('sha256');
      if (hashText == null) {
        throw StateError('Encrypted attachment is missing its integrity hash.');
      }
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
        expectedSha256: base64.decode(base64.normalize(hashText)),
      );
      final source = MediaPlaybackSource(uri: localUri, headers: const {});
      _mediaPlaybackSources[messageId] = source;
      _mediaPlaybackReferences[messageId] =
          (_mediaPlaybackReferences[messageId] ?? 0) + 1;
      return _preparePlaybackSource(messageId, source);
    }
    final uri = await event.getAttachmentUri(skipScanner: false);
    if (uri == null) return null;
    SocksProxy.requireLocalPlayback(uri);
    final source = MediaPlaybackSource(
      uri: uri,
      headers: {
        if (_matrix.accessToken case final token?)
          'Authorization': 'Bearer $token',
      },
    );
    _mediaPlaybackSources[messageId] = source;
    _mediaPlaybackReferences[messageId] =
        (_mediaPlaybackReferences[messageId] ?? 0) + 1;
    return source;
  }

  void _releaseMediaPlaybackSource(String messageId) {
    final references = _mediaPlaybackReferences[messageId];
    if (references != null && references > 1) {
      _mediaPlaybackReferences[messageId] = references - 1;
      return;
    }
    _mediaPlaybackReferences.remove(messageId);
    final source = _mediaPlaybackSources.remove(messageId);
    if (source != null) {
      releaseBrowserMediaUrl(source.uri);
      _mediaRangeProxy.unregister(source.uri);
    }
  }

  Future<MediaPlaybackSource> _preparePlaybackSource(
    String messageId,
    MediaPlaybackSource source,
  ) async {
    try {
      if (!kIsWeb && source.uri.host == '127.0.0.1') {
        await _mediaRangeProxy.prepare(source.uri);
      }
      return source;
    } catch (_) {
      // A failed preparation owns one reference, just like a successful open.
      if (identical(_mediaPlaybackSources[messageId], source)) {
        _releaseMediaPlaybackSource(messageId);
      }
      rethrow;
    }
  }
}
