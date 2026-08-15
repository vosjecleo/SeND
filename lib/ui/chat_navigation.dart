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

  Future<void> _createSpace(BuildContext context) async {
    final name = TextEditingController();
    final topic = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Space'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Space name'),
              ),
              TextField(
                controller: topic,
                decoration: const InputDecoration(
                  labelText: 'Topic (optional)',
                ),
              ),
            ],
          ),
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
    );
    final spaceName = name.text.trim();
    final spaceTopic = topic.text.trim();
    name.dispose();
    topic.dispose();
    if (create == true && spaceName.isNotEmpty) {
      await backend.createSpace(name: spaceName, topic: spaceTopic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff191a1e),
      child: Column(
        children: [
          Expanded(
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
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            key: const Key('create-space-panel'),
            height: _bottomPanelHeightFor(context),
            child: Center(
              child: IconButton(
                tooltip: 'Create Space',
                onPressed: () => _createSpace(context),
                icon: const Icon(Icons.add_box_outlined, size: 27),
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
      child: Align(
        child: SizedBox.square(
          key: ValueKey('space-button-$tooltip'),
          dimension: 48,
          child: Material(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : const Color(0xff2b2d34),
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.hardEdge,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Center(child: child),
            ),
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
    final topic = TextEditingController();
    var presentation = RoomPresentation.text;
    var encrypted = true;
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
              TextField(
                controller: topic,
                decoration: const InputDecoration(
                  labelText: 'Topic (optional)',
                ),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End-to-end encryption'),
                subtitle: const Text('Cannot be disabled after creation.'),
                value: encrypted,
                onChanged: (value) => setDialogState(() => encrypted = value),
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
    final roomTopic = topic.text.trim();
    name.dispose();
    topic.dispose();
    if (create == true && roomName.isNotEmpty) {
      await backend.createRoom(
        name: roomName,
        presentation: presentation,
        topic: roomTopic,
        encrypted: encrypted,
      );
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
          SizedBox(
            key: const Key('current-user-panel'),
            height: _bottomPanelHeightFor(context),
            child: InkWell(
              onTap: () => showOwnProfile(context, backend),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipOval(
                      child: SizedBox.square(
                        dimension: 34,
                        child: backend.profileAvatarBytes == null
                            ? const ColoredBox(
                                color: Color(0xff3a3c46),
                                child: Icon(Icons.person, size: 19),
                              )
                            : Image.memory(
                                backend.profileAvatarBytes!,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        backend.profileDisplayName ??
                            backend.userId
                                ?.split(':')
                                .first
                                .replaceFirst('@', '') ??
                            'Matrix account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox.square(
                      dimension: 36,
                      child: IconButton(
                        tooltip: 'Encryption & recovery',
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          backend.encryptionSetup.status ==
                                  EncryptionSetupStatus.ready
                              ? Icons.verified_user
                              : Icons.gpp_maybe,
                          size: 19,
                        ),
                        onPressed: () => showSecurityCenter(context, backend),
                      ),
                    ),
                    SizedBox.square(
                      dimension: 36,
                      child: IconButton(
                        tooltip: 'Settings',
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            showDeltiecordSettings(context, backend),
                        icon: const Icon(Icons.settings_outlined, size: 19),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: room.name);
    final topic = TextEditingController(text: room.topic);
    var presentation = room.presentation;
    Uint8List? avatar;
    var removeAvatar = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Room settings'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: topic,
                  decoration: const InputDecoration(labelText: 'Topic'),
                  maxLines: 2,
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
                  onSelectionChanged: (value) =>
                      setDialogState(() => presentation = value.first),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose picture'),
                      onPressed: () async {
                        final result = await FilePicker.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        final bytes = result?.files.single.bytes;
                        if (bytes != null) {
                          setDialogState(() {
                            avatar = bytes;
                            removeAvatar = false;
                          });
                        }
                      },
                    ),
                    if (room.avatarBytes != null || avatar != null)
                      TextButton(
                        onPressed: () => setDialogState(() {
                          avatar = null;
                          removeAvatar = true;
                        }),
                        child: const Text('Remove picture'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = controller.text.trim();
    final roomTopic = topic.text.trim();
    controller.dispose();
    topic.dispose();
    if (save != true) return;
    if (name.isNotEmpty && name != room.name) {
      await backend.renameRoom(room.id, name);
    }
    if (roomTopic != room.topic) {
      await backend.setRoomTopic(room.id, roomTopic);
    }
    if (presentation != room.presentation) {
      await backend.setRoomPresentation(room.id, presentation);
    }
    if (avatar != null || removeAvatar) {
      await backend.setRoomAvatar(room.id, avatar);
    }
  }

  @override
  Widget build(BuildContext context) {
    final participantCount = room.voiceParticipants.length;
    if (backend.selectedSpaceId == null && !room.isVoice) {
      return _HomeRoomListTile(backend: backend, room: room);
    }
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      minVerticalPadding: 0,
      selected: backend.selectedRoom?.id == room.id,
      leading: _RoomIcon(room: room, size: 26),
      title: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: room.isVoice
          ? Text(
              participantCount == 0
                  ? 'Nobody connected'
                  : '$participantCount connected',
            )
          : backend.selectedSpaceId == null
          ? Text(room.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
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
                    _edit(context);
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
                  child: Text('Room settings'),
                ),
              ],
            ),
      onTap: () => backend.selectRoom(room.id),
    );
  }
}

class _HomeRoomListTile extends StatelessWidget {
  const _HomeRoomListTile({required this.backend, required this.room});

  final ChatBackend backend;
  final RoomSummary room;

  @override
  Widget build(BuildContext context) {
    final selected = backend.selectedRoom?.id == room.id;
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: 0.42)
          : Colors.transparent,
      child: InkWell(
        onTap: () => backend.selectRoom(room.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _RoomIcon(room: room, size: 34, showPresence: room.isDirect),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        room.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xffb7b8c0),
                          fontSize: 13,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
                if (room.unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Badge(label: Text('${room.unreadCount}')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({
    required this.room,
    required this.size,
    this.showPresence = false,
  });

  final RoomSummary room;
  final double size;
  final bool showPresence;

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
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CircleAvatar(
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
            ),
          ),
          if (showPresence)
            Positioned(
              left: -1,
              bottom: -1,
              child: Container(
                key: ValueKey('presence-${room.id}-${room.presence.name}'),
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (room.presence) {
                    UserPresence.online => const Color(0xff43b581),
                    UserPresence.away => const Color(0xffffc857),
                    UserPresence.offline => const Color(0xff747680),
                  },
                  border: Border.all(color: const Color(0xff202126), width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
