import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'activity_widgets.dart';
import 'advanced_chat_dialogs.dart';
import 'chat_shell.dart' show openDiscussionById;
import 'member_management.dart';
import 'mobile/mobile_profile_sheet.dart';
import 'mobile/mobile_widgets.dart';
import 'navigation_polish.dart';
import 'room_access_dialog.dart';
import 'room_search_panel.dart';

/// Room information uses the same search and conversation paths as the chat.
class RoomDetailsPanel extends StatefulWidget {
  const RoomDetailsPanel({
    required this.backend,
    required this.room,
    required this.onDismiss,
    super.key,
  });

  final ChatBackend backend;
  final RoomSummary room;
  final VoidCallback onDismiss;

  @override
  State<RoomDetailsPanel> createState() => _RoomDetailsPanelState();
}

class _RoomDetailsPanelState extends State<RoomDetailsPanel> {
  int _section = 0;
  Future<List<ChatMessage>>? _pins;

  @override
  void didUpdateWidget(RoomDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _section = 0;
      _pins = null;
    }
  }

  Future<void> _open(String eventId) async {
    if (widget.backend.selectedRoom?.id != widget.room.id) return;
    widget.onDismiss();
    await widget.backend.jumpToEvent(eventId);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.backend,
    builder: (context, _) {
      final backend = widget.backend;
      final room = widget.room;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: widget.onDismiss,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () =>
                  showRoomSearchSheet(context, backend, onOpen: _open),
            ),
            IconButton(
              tooltip: 'Notifications',
              icon: Icon(
                backend.selectedRoomMuted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_outlined,
              ),
              onPressed: () =>
                  showRoomNotificationControls(context, backend, room),
            ),
            if (!room.isDirect)
              IconButton(
                tooltip: 'Room settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () =>
                    showRoomAccessDialog(context, backend, room.id),
              ),
            MemberRoomTools(backend: backend, room: room),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    MobileRoomAvatar(room: room, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            room.isDirect ? 'Direct message' : 'Channel',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (room.topic.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    room.topic,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              DefaultTabController(
                key: ValueKey(room.id),
                length: 6,
                initialIndex: _section,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  onTap: (index) => setState(() {
                    _section = index;
                    if (index == 2) _pins = null;
                  }),
                  tabs: const [
                    Tab(text: 'Members'),
                    Tab(text: 'Media'),
                    Tab(text: 'Pins'),
                    Tab(text: 'Threads'),
                    Tab(text: 'Links'),
                    Tab(text: 'Files'),
                  ],
                ),
              ),
              Expanded(
                child: switch (_section) {
                  0 => _members(context),
                  2 => FutureBuilder<List<ChatMessage>>(
                    future: _pins ??= backend.loadPinnedMessages(),
                    builder: (context, snapshot) => snapshot.hasError
                        ? Center(
                            child: TextButton(
                              onPressed: () => setState(
                                () => _pins = backend.loadPinnedMessages(),
                              ),
                              child: const Text('Retry loading pins'),
                            ),
                          )
                        : !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : _messages(snapshot.data!, 'No pinned messages.'),
                  ),
                  3 => _messages(
                    backend.messages
                        .where((m) => m.threadReplyCount > 0)
                        .toList(),
                    'No threads in loaded history.',
                    threads: true,
                  ),
                  _ => RoomSearchPanel(
                    key: ValueKey('${room.id}:$_section'),
                    backend: backend,
                    onOpen: _open,
                    embedded: true,
                    initialSection: switch (_section) {
                      1 => RoomSearchSection.media,
                      4 => RoomSearchSection.links,
                      _ => RoomSearchSection.files,
                    },
                  ),
                },
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _messages(
    List<ChatMessage> messages,
    String empty, {
    bool threads = false,
  }) => messages.isEmpty
      ? Center(child: Text(empty))
      : ListView.builder(
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return ListTile(
              leading: Icon(
                threads ? Icons.forum_outlined : Icons.push_pin_outlined,
              ),
              title: Text(message.sender),
              subtitle: Text(
                message.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                if (threads) {
                  openDiscussionById(
                    context,
                    widget.backend,
                    widget.room.id,
                    message.id,
                  );
                } else {
                  _open(message.id);
                }
              },
            );
          },
        );

  Widget _members(BuildContext context) {
    final backend = widget.backend;
    final members = [...backend.selectedRoomMembers]
      ..sort((a, b) {
        final offline = (a.presence == UserPresence.offline ? 1 : 0).compareTo(
          b.presence == UserPresence.offline ? 1 : 0,
        );
        return offline != 0
            ? offline
            : a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              );
      });
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (backend.canInviteToRoom(widget.room.id))
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Invite members'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  showInviteMember(context, backend, roomId: widget.room.id),
            ),
          ),
        for (final online in [true, false]) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '${online ? 'Online' : 'Offline'} — ${members.where((m) => (m.presence != UserPresence.offline) == online).length}',
            ),
          ),
          for (final member in members.where(
            (m) => (m.presence != UserPresence.offline) == online,
          ))
            ListTile(
              leading: MobileAvatar(
                size: 36,
                bytes: member.avatarBytes,
                fallback: member.displayName,
                userId: member.userId,
                presence: member.presence,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: member.nameColor == null
                            ? null
                            : Color(member.nameColor!),
                      ),
                    ),
                  ),
                  if (member.powerLevel >= 50)
                    MemberRoleBadge(powerLevel: member.powerLevel),
                ],
              ),
              subtitle: !online
                  ? null
                  : ActivityStatus(
                      backend: backend,
                      userId: member.userId,
                      presence: member.presence,
                      status: member.statusMessage,
                    ),
              onTap: () =>
                  showMobileProfileSheet(context, backend, member.userId),
              onLongPress: () => showMemberManagement(context, backend, member),
            ),
        ],
      ],
    );
  }
}
