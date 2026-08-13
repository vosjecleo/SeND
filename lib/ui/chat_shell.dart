import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'security_center.dart';

class ChatShell extends StatefulWidget {
  const ChatShell({required this.backend, super.key});

  final ChatBackend backend;

  @override
  State<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends State<ChatShell> {
  final _message = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _message.clear();
    try {
      await widget.backend.sendMessage(text);
    } catch (_) {
      if (mounted) _message.text = text;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (widget.backend.encryptionSetup.needsAttention)
            _SecurityBanner(backend: widget.backend),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 68, child: _SpaceBar(backend: widget.backend)),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 280,
                  child: _RoomPanel(backend: widget.backend),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: widget.backend.selectedRoom == null
                      ? const _EmptyConversation()
                      : _Conversation(
                          backend: widget.backend,
                          controller: _message,
                          sending: _sending,
                          onSend: _send,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff4b3c19),
    child: InkWell(
      onTap: () => showSecurityCenter(context, backend),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 19),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Encrypted history is not fully protected on this device.',
              ),
            ),
            TextButton(
              onPressed: () => showSecurityCenter(context, backend),
              child: const Text('Fix encryption'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SpaceBar extends StatelessWidget {
  const _SpaceBar({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff191a1e),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        children: [
          _SpaceButton(
            tooltip: 'Home',
            selected: backend.selectedSpaceId == null,
            onTap: () => backend.selectSpace(null),
            child: const Icon(Icons.home_filled, size: 21),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Divider(height: 1),
          ),
          for (final space in backend.spaces)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _SpaceButton(
                tooltip: space.name,
                selected: backend.selectedSpaceId == space.id,
                onTap: () => backend.selectSpace(space.id),
                child: space.avatarBytes == null
                    ? Text(
                        _initials(space.name),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Image.memory(
                        space.avatarBytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }
}

class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 48,
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : const Color(0xff2b2d34),
          borderRadius: BorderRadius.circular(selected ? 13 : 24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(selected ? 13 : 24),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _RoomPanel extends StatelessWidget {
  const _RoomPanel({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff202126),
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xff35363d))),
            ),
            child: Text(
              backend.selectedSpaceId == null
                  ? 'Home'
                  : backend.spaces
                            .where(
                              (space) => space.id == backend.selectedSpaceId,
                            )
                            .map((space) => space.name)
                            .firstOrNull ??
                        'Space',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: backend.rooms.isEmpty
                ? const Center(child: Text('No joined rooms'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: backend.rooms.length,
                    itemBuilder: (context, index) {
                      final room = backend.rooms[index];
                      final selected = backend.selectedRoom?.id == room.id;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        leading: _RoomIcon(room: room, size: 30),
                        title: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          room.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: room.unreadCount > 0
                            ? Badge(label: Text('${room.unreadCount}'))
                            : null,
                        onTap: () => backend.selectRoom(room.id),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: Text(
              backend.userId ?? 'Matrix account',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Encryption & recovery',
              icon: Icon(
                backend.encryptionSetup.status == EncryptionSetupStatus.ready
                    ? Icons.verified_user
                    : Icons.gpp_maybe,
                size: 19,
              ),
              onPressed: () => showSecurityCenter(context, backend),
            ),
          ),
          SizedBox(
            height: 34,
            child: TextButton.icon(
              onPressed: backend.logout,
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Log out'),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({required this.room, required this.size});

  final RoomSummary room;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (room.usesChannelIcon) {
      return SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.tag, size: 18),
      );
    }
    final avatar = room.avatarBytes;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xff3a3c46),
      backgroundImage: avatar == null ? null : MemoryImage(avatar),
      child: avatar == null
          ? Text(
              room.name.trim().isEmpty
                  ? '?'
                  : room.name.trim().characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.backend,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final ChatBackend backend;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final room = backend.selectedRoom!;
    return Column(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            color: Color(0xff292a30),
            border: Border(bottom: BorderSide(color: Color(0xff35363d))),
          ),
          child: Row(
            children: [
              _RoomIcon(room: room, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  room.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (backend.error case final error?)
          MaterialBanner(
            content: Text(error),
            actions: [
              TextButton(
                onPressed: backend.clearError,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Expanded(
          child: backend.timelineLoading
              ? const Center(child: CircularProgressIndicator())
              : backend.messages.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: backend.messages.length,
                  itemBuilder: (context, index) =>
                      _MessageRow(message: backend.messages[index]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          child: TextField(
            controller: controller,
            enabled: !sending,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Message #${room.name}',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Send',
                onPressed: sending ? null : onSend,
                icon: const Icon(Icons.send, size: 20),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final local = message.timestamp.toLocal();
    final time = TimeOfDay.fromDateTime(local).format(context);
    return Opacity(
      opacity: message.pending ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                message.sender,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: SelectableText(message.body)),
            const SizedBox(width: 12),
            Text(time, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forum_outlined, size: 46),
        SizedBox(height: 12),
        Text('Choose a room to start chatting'),
      ],
    ),
  );
}
