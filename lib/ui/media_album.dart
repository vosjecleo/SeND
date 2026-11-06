import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../backend/chat_backend.dart';
import '../services/spoiler_reveals.dart';
import 'deltiecord_theme.dart';
import 'lifecycle_memory_image.dart';
import 'timeline_media_geometry.dart';

import '../models/chat_models.dart';

/// Groups explicit upload batches; adjacency is only a legacy fallback.
/// Event IDs and server order stay intact. Only their presentation is grouped.
class MediaAlbumIndex {
  MediaAlbumIndex._(
    this.albums,
    this.hiddenMessageIds,
    this.roomId,
    this.segmentId,
    this._olderVisible,
  );

  factory MediaAlbumIndex.fromNewestFirst(
    List<ChatMessage> messages, {
    String? roomId,
    String? segmentId,
  }) {
    final albums = <String, List<ChatMessage>>{};
    final hidden = <String>{};
    final tagged = <(String, String, String?), List<ChatMessage>>{};
    for (final message in messages) {
      final gallery = message.attachment?.gallery;
      if (gallery == null ||
          !gallery.isValid ||
          gallery.count <= 1 ||
          message.senderId == null ||
          message.failed ||
          message.redacted ||
          message.system ||
          message.attachment!.sticker ||
          !{
            AttachmentKind.image,
            AttachmentKind.video,
          }.contains(message.attachment!.kind)) {
        continue;
      }
      tagged
          .putIfAbsent((
            gallery.id,
            message.senderId!,
            message.threadRootId,
          ), () => [])
          .add(message);
    }
    for (final run in tagged.values) {
      final count = run.first.attachment!.gallery!.count;
      final indices = run.map((m) => m.attachment!.gallery!.index).toSet();
      // Contradictory metadata must never hide distinct messages.
      if (run.any((m) => m.attachment!.gallery!.count != count) ||
          indices.length != run.length ||
          run.length > count) {
        continue;
      }
      final anchor = run.last; // Earliest loaded event, not newest arrival.
      final ordered = List<ChatMessage>.of(run)
        ..sort(
          (a, b) => a.attachment!.gallery!.index.compareTo(
            b.attachment!.gallery!.index,
          ),
        );
      albums[anchor.id] = ordered;
      hidden.addAll(run.where((m) => m.id != anchor.id).map((m) => m.id));
    }
    for (var index = 0; index < messages.length;) {
      final first = messages[index];
      if (!_eligible(first)) {
        index++;
        continue;
      }
      final run = <ChatMessage>[first];
      var cursor = index + 1;
      while (cursor < messages.length) {
        // A caption introduces its upload group. Do not absorb older messages.
        if (run.last.attachment?.caption?.trim().isNotEmpty == true) break;
        final candidate = messages[cursor];
        final newer = run.last;
        if (!_eligible(candidate) ||
            !DateUtils.isSameDay(
              newer.timestamp.toLocal(),
              candidate.timestamp.toLocal(),
            ) ||
            candidate.senderId != first.senderId ||
            candidate.sender != first.sender ||
            newer.timestamp.difference(candidate.timestamp).abs() >=
                const Duration(minutes: 5)) {
          break;
        }
        run.add(candidate);
        cursor++;
      }
      if (run.length > 1) {
        albums[first.id] = run.reversed.toList(growable: false);
        hidden.addAll(run.skip(1).map((message) => message.id));
      }
      index = cursor;
    }
    final olderVisible = <String, ChatMessage?>{};
    ChatMessage? older;
    for (final message in messages.reversed) {
      if (hidden.contains(message.id)) continue;
      olderVisible[message.id] = older;
      older = message;
    }
    return MediaAlbumIndex._(albums, hidden, roomId, segmentId, olderVisible);
  }

  final Map<String, List<ChatMessage>> albums;
  final Set<String> hiddenMessageIds;
  final String? roomId;
  final String? segmentId;
  final Map<String, ChatMessage?> _olderVisible;
  ChatMessage? olderVisibleMessage(String id) => _olderVisible[id];
  String rowIdentity(ChatMessage message) {
    final gallery = albums[message.id]?.first.attachment?.gallery;
    return gallery == null
        ? message.timelineKey
        : 'send-gallery:${jsonEncode([roomId, segmentId, message.senderId, message.threadRootId, gallery.id])}';
  }

  String visibleMessageId(String eventId) {
    if (!hiddenMessageIds.contains(eventId)) return eventId;
    for (final entry in albums.entries) {
      if (entry.value.any((m) => m.id == eventId)) return entry.key;
    }
    return eventId;
  }

  static bool _eligible(ChatMessage message) {
    final attachment = message.attachment;
    if (attachment == null ||
        attachment.gallery != null ||
        attachment.hasGalleryMetadata ||
        message.pending ||
        message.queued ||
        message.failed ||
        attachment.sticker ||
        attachment.animated ||
        message.system ||
        message.redacted ||
        message.poll != null ||
        message.reply != null) {
      return false;
    }
    return attachment.kind == AttachmentKind.image ||
        attachment.kind == AttachmentKind.video;
  }
}

/// Stable row identities and scroll/jump aliases for explicitly tagged galleries.
class GalleryRowKeys {
  final _cards = <String, GlobalKey>{};

  /// Alias hidden members for jumping, but mount each key only on its card.
  void bind(MediaAlbumIndex index, Map<String, GlobalKey> rows) {
    final previous = _cards.values.toSet();
    rows.removeWhere((_, key) => previous.contains(key));
    final identities = <String>{};
    for (final entry in index.albums.entries) {
      final members = entry.value;
      if (members.first.attachment?.gallery == null) continue;
      final anchor = members.firstWhere((m) => m.id == entry.key);
      final id = index.rowIdentity(anchor);
      identities.add(id);
      final key = _cards.putIfAbsent(id, GlobalKey.new);
      for (final member in members) {
        rows[member.id] = key;
        rows[member.timelineKey] = key;
      }
    }
    _cards.removeWhere((id, _) => !identities.contains(id));
  }
}

/// Three-cell album: one item on the left, two on the right, then a +N tile.
class MediaAlbumGrid extends StatelessWidget {
  const MediaAlbumGrid({
    required this.messages,
    required this.itemBuilder,
    this.height = 280,
    this.mobile = false,
    super.key,
  });

  final List<ChatMessage> messages;
  final Widget Function(BuildContext context, ChatMessage message) itemBuilder;
  final double height;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    Widget tile(int index) {
      final message = messages[index];
      final remaining = messages.length - 3;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            itemBuilder(context, message),
            if (index == 2 && remaining > 0) ...[
              ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
              Center(
                child: Text(
                  '+$remaining',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final count = messages.length.clamp(1, 3);
    final captions = messages
        .where((m) => m.attachment?.caption?.trim().isNotEmpty == true)
        .toList();
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: timelineMediaWidthLimit(
            MediaQuery.sizeOf(context),
            mobile: mobile,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final message in captions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  message.attachment!.caption!,
                  key: ValueKey('album-caption-${message.id}'),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: height,
                child: count == 1
                    ? tile(0)
                    : count == 2
                    ? Row(
                        children: [
                          Expanded(child: tile(0)),
                          const SizedBox(width: 2),
                          Expanded(child: tile(1)),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: tile(0)),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(child: tile(1)),
                                const SizedBox(height: 2),
                                Expanded(child: tile(2)),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Album cells own their bounds. Do not fit a letterboxed standalone media
/// widget into another box: that scales its blank space along with the image.
class MediaAlbumTile extends StatefulWidget {
  const MediaAlbumTile({
    required this.backend,
    required this.message,
    required this.onOpen,
    this.dimPending = true,
    super.key,
  });
  final ChatBackend backend;
  final ChatMessage message;
  final VoidCallback onOpen;
  final bool dimPending;
  @override
  State<MediaAlbumTile> createState() => _MediaAlbumTileState();
}

class _MediaAlbumTileState extends State<MediaAlbumTile> {
  Future<Uint8List>? _bytes;
  AttachmentDraft? _sourceDraft;
  Future<Uint8List> _load() async {
    final draft =
        widget.backend.queuedAttachment(widget.message.id) ??
        widget.backend.queuedAttachment(widget.message.transactionId ?? '');
    _sourceDraft = draft;
    if (draft != null) {
      final bytes = draft.mimeType.startsWith('image/')
          ? draft.bytes
          : draft.videoThumbnail;
      if (bytes != null && bytes.isNotEmpty) return bytes;
      throw StateError('Preview is not ready.');
    }
    try {
      return await widget.backend.downloadAttachment(
        widget.message.id,
        thumbnail: true,
      );
    } catch (_) {
      if (widget.message.attachment!.kind == AttachmentKind.video) rethrow;
      return widget.backend.downloadAttachment(widget.message.id);
    }
  }

  @override
  void didUpdateWidget(MediaAlbumTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final draft =
        widget.backend.queuedAttachment(widget.message.id) ??
        widget.backend.queuedAttachment(widget.message.transactionId ?? '');
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.backend != widget.backend ||
        !identical(_sourceDraft?.bytes, draft?.bytes) ||
        !identical(_sourceDraft?.videoThumbnail, draft?.videoThumbnail) ||
        oldWidget.message.attachment?.sourceEventId !=
            widget.message.attachment?.sourceEventId) {
      _bytes = null;
      _sourceDraft = draft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.message.attachment!;
    return Opacity(
      opacity: widget.dimPending && widget.message.pending ? .55 : 1,
      child: _buildTile(context, attachment),
    );
  }

  Widget _buildTile(BuildContext context, ChatAttachment attachment) {
    final reveals = SpoilerReveals.forBackend(widget.backend);
    if (attachment.spoiler && !reveals.contains(widget.message.id)) {
      return Material(
        color: context.deltiecord.input.withValues(alpha: 1),
        child: InkWell(
          onTap: () => setState(() => reveals.reveal(widget.message.id)),
          child: const Center(child: Icon(Icons.visibility_off_outlined)),
        ),
      );
    }
    _bytes ??= _load();
    return InkWell(
      onTap: widget.message.pending ? null : widget.onOpen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return LifecycleMemoryImage(
                  bytes: snapshot.data!,
                  decodeWidth: 840,
                  animated: attachment.animated,
                  autoplay:
                      widget.backend.preferences.autoplayGifs &&
                      !widget.backend.preferences.reducedMotion,
                  fit: BoxFit.cover,
                );
              }
              if (snapshot.hasError) {
                if (widget.message.pending) return const SizedBox.expand();
                return Center(
                  child: IconButton(
                    tooltip: 'Retry preview',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() => _bytes = _load()),
                  ),
                );
              }
              return const Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          ),
          if (attachment.kind == AttachmentKind.video)
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 40,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
