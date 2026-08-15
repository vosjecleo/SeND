part of 'chat_shell.dart';

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

  Future<void> _createRoom(BuildContext context) async {
    final name = TextEditingController();
    var presentation = RoomPresentation.text;
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            backend.selectedSpaceId == null
                ? 'Create chat room'
                : 'Create channel',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Room name'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<RoomPresentation>(
                segments: const [
                  ButtonSegment(
                    value: RoomPresentation.text,
                    icon: Icon(Icons.tag),
                    label: Text('Text'),
                  ),
                  ButtonSegment(
                    value: RoomPresentation.voice,
                    icon: Icon(Icons.volume_up_outlined),
                    label: Text('Voice'),
                  ),
                ],
                selected: {presentation},
                onSelectionChanged: (selection) =>
                    setDialogState(() => presentation = selection.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final roomName = name.text.trim();
    name.dispose();
    if (create == true && roomName.isNotEmpty) {
      await backend.createRoom(name: roomName, presentation: presentation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textRooms = backend.rooms.where((room) => !room.isVoice).toList();
    final voiceRooms = backend.rooms.where((room) => room.isVoice).toList();
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    backend.selectedSpaceId == null
                        ? 'Home'
                        : backend.spaces
                                  .where(
                                    (space) =>
                                        space.id == backend.selectedSpaceId,
                                  )
                                  .map((space) => space.name)
                                  .firstOrNull ??
                              'Space',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Create room',
                  onPressed: () => _createRoom(context),
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: backend.rooms.isEmpty
                ? const Center(child: Text('No joined rooms'))
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      if (backend.selectedSpaceId != null &&
                          textRooms.isNotEmpty)
                        const _RoomSectionLabel('TEXT ROOMS'),
                      for (final room in textRooms)
                        _RoomListTile(backend: backend, room: room),
                      if (voiceRooms.isNotEmpty)
                        const _RoomSectionLabel('VOICE ROOMS'),
                      for (final room in voiceRooms)
                        _RoomListTile(backend: backend, room: room),
                    ],
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Encryption & recovery',
                  icon: Icon(
                    backend.encryptionSetup.status ==
                            EncryptionSetupStatus.ready
                        ? Icons.verified_user
                        : Icons.gpp_maybe,
                    size: 19,
                  ),
                  onPressed: () => showSecurityCenter(context, backend),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => showDeltiecordSettings(context, backend),
                  icon: const Icon(Icons.settings_outlined, size: 19),
                ),
              ],
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

class _RoomSectionLabel extends StatelessWidget {
  const _RoomSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 9, 10, 3),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xff989aa5),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _RoomListTile extends StatelessWidget {
  const _RoomListTile({required this.backend, required this.room});

  final ChatBackend backend;
  final RoomSummary room;

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: room.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename room'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await backend.renameRoom(room.id, name);
  }

  @override
  Widget build(BuildContext context) {
    final participantCount = room.voiceParticipants.length;
    return ListTile(
      dense: true,
      selected: backend.selectedRoom?.id == room.id,
      leading: _RoomIcon(room: room, size: 30),
      title: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        room.isVoice
            ? participantCount == 0
                  ? 'Nobody connected'
                  : '$participantCount connected'
            : room.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: backend.selectedSpaceId == null
          ? room.unreadCount > 0
                ? Badge(label: Text('${room.unreadCount}'))
                : null
          : PopupMenuButton<String>(
              tooltip: 'Edit room',
              iconSize: 17,
              onSelected: (action) {
                switch (action) {
                  case 'rename':
                    _rename(context);
                  case 'text':
                    backend.setRoomPresentation(room.id, RoomPresentation.text);
                  case 'voice':
                    backend.setRoomPresentation(
                      room.id,
                      RoomPresentation.voice,
                    );
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: 'text',
                  checked: !room.isVoice,
                  child: const Text('Text room'),
                ),
                CheckedPopupMenuItem(
                  value: 'voice',
                  checked: room.isVoice,
                  child: const Text('Voice room'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('Rename room'),
                ),
              ],
            ),
      onTap: () => backend.selectRoom(room.id),
    );
  }
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({required this.room, required this.size});

  final RoomSummary room;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (room.isVoice) {
      return SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.volume_up_outlined, size: 18),
      );
    }
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
