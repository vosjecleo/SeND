import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

/// One menu for Home and Archive, regardless of desktop/touch navigation.
Future<void> showHomeRoomMenu(
  BuildContext context,
  ChatBackend backend,
  RoomSummary room, {
  Offset? position,
}) async {
  final data = backend.personalData;
  final pinned = data?.pinned(room.id) ?? false,
      archived = data?.archived(room.id) ?? false;
  final muted =
      room.notificationMode == RoomNotificationMode.muted ||
      (room.mutedUntil?.isAfter(DateTime.now()) ?? false);
  final items = <(String, String, IconData)>[
    ('read', 'Mark as read', Icons.done_all),
    (
      'mute',
      muted ? 'Unmute room' : 'Mute room',
      muted ? Icons.notifications_outlined : Icons.notifications_off_outlined,
    ),
    (
      'pin',
      pinned ? 'Unpin' : 'Pin',
      pinned ? Icons.push_pin : Icons.push_pin_outlined,
    ),
    (
      'archive',
      archived ? 'Unarchive' : 'Archive',
      archived ? Icons.unarchive_outlined : Icons.archive_outlined,
    ),
  ];
  String? action;
  if (position != null) {
    final size = MediaQuery.sizeOf(context);
    action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & size,
      ),
      items: [
        for (final item in items)
          PopupMenuItem(
            value: item.$1,
            enabled: !['pin', 'archive'].contains(item.$1) || data != null,
            child: Row(
              children: [
                Icon(item.$3, size: 18),
                const SizedBox(width: 12),
                Text(item.$2),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'leave',
          child: Row(
            children: [
              Icon(
                Icons.logout,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              const Text('Leave'),
            ],
          ),
        ),
      ],
    );
  } else {
    action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              ListTile(
                leading: Icon(item.$3),
                title: Text(item.$2),
                enabled: !['pin', 'archive'].contains(item.$1) || data != null,
                onTap: () => Navigator.pop(sheet, item.$1),
              ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: Theme.of(sheet).colorScheme.error,
              ),
              title: const Text('Leave'),
              onTap: () => Navigator.pop(sheet, 'leave'),
            ),
          ],
        ),
      ),
    );
  }
  if (!context.mounted || action == null) return;
  try {
    switch (action) {
      case 'read':
        await backend.markRoomUnread(room.id, false);
      case 'mute':
        await backend.setRoomMuted(room.id, !muted);
      case 'pin':
        await backend.pinDirectRoom(room.id, !pinned);
      case 'archive':
        await backend.archiveRoom(room.id, !archived);
      case 'leave':
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text('Leave ${room.name}?'),
            content: const Text('You may need another invitation to rejoin.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (yes == true) await backend.leaveRoom(room.id);
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update this chat. Try again.')),
      );
    }
  }
}

class MutedAvatar extends StatelessWidget {
  const MutedAvatar({required this.muted, required this.child, super.key});
  final bool muted;
  final Widget child;
  @override
  Widget build(BuildContext context) => !muted
      ? child
      : Opacity(
          opacity: .55,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              .2126,
              .7152,
              .0722,
              0,
              0,
              .2126,
              .7152,
              .0722,
              0,
              0,
              .2126,
              .7152,
              .0722,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: child,
          ),
        );
}

bool roomIsMuted(RoomSummary room) =>
    room.notificationMode == RoomNotificationMode.muted ||
    (room.mutedUntil?.isAfter(DateTime.now()) ?? false);
