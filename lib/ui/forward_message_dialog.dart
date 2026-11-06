import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/message_forwarding.dart';
import 'mobile/mobile_widgets.dart' show MobileAvatar;

bool canForwardMessage(ChatMessage message) =>
    !message.pending &&
    !message.failed &&
    !message.redacted &&
    !message.decryptionPending &&
    !message.system &&
    message.poll == null &&
    message.attachment?.sticker != true;

Future<void> showForwardMessageDialog(
  BuildContext context,
  ChatBackend backend,
  List<ChatMessage> messages, {
  String? sourceRoomId,
}) async {
  if (messages.isEmpty) return;
  if (messages.any((m) => !canForwardMessage(m))) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('This gallery is not ready to forward yet.'),
        ),
      );
    }
    return;
  }
  // Desktop menus live in an OverlayPortal which disappears as soon as the
  // action is selected. Keep the dialog flow on its owning navigator instead.
  final navigator = Navigator.of(context, rootNavigator: true);
  final dialogContext = navigator.context;
  final userId = backend.userId;
  final source = sourceRoomId ?? backend.roomIdForMessage(messages.first.id);
  if (source == null) return;
  final ids = messages.map((m) => m.id).toList(growable: false);
  final destination = await showDialog<RoomSummary>(
    context: dialogContext,
    builder: (_) => _ForwardDestination(backend: backend),
  );
  if (destination == null ||
      !dialogContext.mounted ||
      backend.userId != userId) {
    return;
  }
  if (!destination.encrypted) {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (dialog) => AlertDialog(
        title: const Text('Forward without encryption?'),
        content: Text(
          '${destination.name} is not encrypted. People with access '
          'to its history can read these messages and open their attachments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Forward'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !dialogContext.mounted ||
        backend.userId != userId) {
      return;
    }
  }
  await showDialog<void>(
    context: dialogContext,
    barrierDismissible: false,
    builder: (_) => _ForwardProgress(
      send: () => backend.forwardMessages(
        sourceRoomId: source,
        eventIds: ids,
        destinationRoomId: destination.id,
        allowUnencrypted: !destination.encrypted,
      ),
    ),
  );
}

class _ForwardDestination extends StatefulWidget {
  const _ForwardDestination({required this.backend});
  final ChatBackend backend;
  @override
  State<_ForwardDestination> createState() => _ForwardDestinationState();
}

class _ForwardDestinationState extends State<_ForwardDestination> {
  String _query = '';
  RoomSummary? _selected;
  final _avatars = <String, Future<Uint8List?>>{};
  late final _rooms = {
    for (final room in widget.backend.forwardingRooms)
      if (widget.backend.canSendMessagesToRoom(room.id)) room.id: room,
  }.values.toList(growable: false);
  late final _parents = _indexParents();
  Map<String, SpaceSummary> _indexParents() {
    final spaces = List<SpaceSummary>.of(widget.backend.spaces)
      ..sort((a, b) {
        if (a.id == b.id) return 0;
        if (a.id == widget.backend.selectedSpaceId) return -1;
        if (b.id == widget.backend.selectedSpaceId) return 1;
        return a.id.compareTo(b.id);
      });
    final parents = <String, SpaceSummary>{};
    for (final space in spaces) {
      for (final room in widget.backend.roomsInSpace(space.id)) {
        parents.putIfAbsent(room.id, () => space);
      }
    }
    return parents;
  }

  SpaceSummary? _parent(RoomSummary room) => _parents[room.id];

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms
        .where(
          (r) =>
              r.name.toLowerCase().contains(_query) ||
              (_parent(r)?.name.toLowerCase().contains(_query) ?? false),
        )
        .toList();
    return AlertDialog(
      title: const Text('Forward to'),
      content: SizedBox(
        width: 420,
        height: 340,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search chats and channels',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rooms.isEmpty
                  ? const Center(child: Text('No chats found'))
                  : ListView.builder(
                      itemCount: rooms.length,
                      itemBuilder: (context, index) {
                        final room = rooms[index];
                        final parent = _parent(room);
                        return ListTile(
                          selected: _selected?.id == room.id,
                          leading: FutureBuilder<Uint8List?>(
                            future: _avatars.putIfAbsent(
                              room.id,
                              () =>
                                  widget.backend.loadForwardingAvatar(room.id),
                            ),
                            initialData:
                                parent?.avatarBytes ?? room.avatarBytes,
                            builder: (_, snapshot) => MobileAvatar(
                              bytes: snapshot.data,
                              fallback: parent?.name ?? room.name,
                              size: 36,
                            ),
                          ),
                          title: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: room.name),
                                if (parent != null)
                                  TextSpan(
                                    text: ' · ${parent.name}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _selected?.id == room.id
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => setState(() => _selected = room),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Forward'),
        ),
      ],
    );
  }
}

class _ForwardProgress extends StatefulWidget {
  const _ForwardProgress({required this.send});
  final Future<void> Function() send;
  @override
  State<_ForwardProgress> createState() => _ForwardProgressState();
}

class _ForwardProgressState extends State<_ForwardProgress> {
  String? _error;
  @override
  void initState() {
    super.initState();
    _send();
  }

  Future<void> _send() async {
    try {
      await widget.send();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ForwardingFailure && error.sent > 0
            ? '${error.sent} of ${error.total} messages forwarded. The remaining messages were not sent.'
            : 'Could not forward these messages. Check your connection and that the original messages are still available.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _error != null,
    child: AlertDialog(
      title: Text(_error == null ? 'Forwarding…' : 'Forwarding failed'),
      content: _error == null
          ? const SizedBox(
              height: 40,
              child: Center(child: CircularProgressIndicator()),
            )
          : Text(_error!),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
      ],
    ),
  );
}
