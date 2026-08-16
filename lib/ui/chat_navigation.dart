part of 'chat_shell.dart';

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

  Future<void> _searchSpaces(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => _SpaceSearchDialog(backend: backend),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.deltiecord.rail,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                vertical: _densityBetween(
                  backend.preferences.compactness,
                  roomy: 9,
                  compact: 5,
                ),
                horizontal: 8,
              ),
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
                    padding: EdgeInsets.only(
                      bottom: _densityBetween(
                        backend.preferences.compactness,
                        roomy: 8,
                        compact: 4,
                      ),
                    ),
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
                Padding(
                  key: const Key('create-space-panel'),
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: _SpaceButton(
                    tooltip: 'Create Space',
                    selected: false,
                    onTap: () => _createSpace(context),
                    child: const Icon(Icons.add, size: 25),
                  ),
                ),
                _SpaceButton(
                  tooltip: 'Search for Spaces',
                  selected: false,
                  onTap: () => _searchSpaces(context),
                  child: const Icon(Icons.travel_explore_outlined, size: 23),
                ),
              ],
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

class _SpaceSearchDialog extends StatefulWidget {
  const _SpaceSearchDialog({required this.backend});

  final ChatBackend backend;

  @override
  State<_SpaceSearchDialog> createState() => _SpaceSearchDialogState();
}

class _SpaceSearchDialogState extends State<_SpaceSearchDialog> {
  final _query = TextEditingController();
  List<SpaceDirectoryEntry> _results = const [];
  bool _searching = false;
  String? _error;
  int _generation = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.backend.searchPublicSpaces(query);
      if (!mounted || generation != _generation) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'The Space directory search failed.');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _join(String roomId) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      await widget.backend.joinPublicSpace(roomId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = 'Deltiecord could not join that Space.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Search for Spaces'),
    content: SizedBox(
      width: 520,
      height: 430,
      child: Column(
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search the public Matrix Space directory',
              prefixIcon: const Icon(Icons.travel_explore_outlined),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _searching ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (_error case final error?)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(error)),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty && !_searching
                ? const Center(child: Text('No public Spaces found yet.'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final space = _results[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundImage: space.avatarBytes == null
                              ? null
                              : MemoryImage(space.avatarBytes!),
                          child: space.avatarBytes == null
                              ? const Icon(Icons.workspaces_outline, size: 18)
                              : null,
                        ),
                        title: Text(space.name),
                        subtitle: Text(
                          [
                            '${space.memberCount} members',
                            if (space.topic.trim().isNotEmpty) space.topic,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: _searching
                              ? null
                              : () => _join(space.roomId),
                          child: const Text('Join'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Close'),
      ),
    ],
  );
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
                : context.deltiecord.elevated,
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

class _RoomPanel extends StatefulWidget {
  const _RoomPanel({required this.backend});

  final ChatBackend backend;

  @override
  State<_RoomPanel> createState() => _RoomPanelState();
}

class _RoomPanelState extends State<_RoomPanel> {
  final _roomSearchController = TextEditingController();
  String _roomQuery = '';

  ChatBackend get backend => widget.backend;

  @override
  void dispose() {
    _roomSearchController.dispose();
    super.dispose();
  }

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

  Future<void> _startDirectMessage(BuildContext context) async {
    final matrixId = await showDialog<String>(
      context: context,
      builder: (context) => const _StartDirectMessageDialog(),
    );
    if (matrixId != null && RegExp(r'^@[^:]+:.+$').hasMatch(matrixId)) {
      await backend.startDirectChat(matrixId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _roomQuery.trim().toLowerCase();
    final visibleRooms = query.isEmpty
        ? backend.rooms
        : backend.rooms
              .where(
                (room) =>
                    room.name.toLowerCase().contains(query) ||
                    room.topic.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final textRooms = visibleRooms.where((room) => !room.isVoice).toList();
    final voiceRooms = visibleRooms.where((room) => room.isVoice).toList();
    return Material(
      color: context.deltiecord.panel,
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: context.deltiecord.surface,
              border: Border(
                bottom: BorderSide(color: context.deltiecord.divider),
              ),
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
                PopupMenuButton<String>(
                  tooltip: backend.selectedSpaceId == null
                      ? 'Start chat or create room'
                      : 'Create room',
                  icon: const Icon(Icons.add, size: 20),
                  onSelected: (value) {
                    if (value == 'direct') _startDirectMessage(context);
                    if (value == 'room') _createRoom(context);
                  },
                  itemBuilder: (context) => [
                    if (backend.selectedSpaceId == null)
                      const PopupMenuItem(
                        value: 'direct',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.person_add_alt_1_outlined),
                          title: Text('Start direct message'),
                        ),
                      ),
                    PopupMenuItem(
                      value: 'room',
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.add_comment_outlined),
                        title: Text(
                          backend.selectedSpaceId == null
                              ? 'Create group chat'
                              : 'Create room',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 3),
            child: SizedBox(
              height: 34,
              child: TextField(
                key: const Key('room-list-search'),
                controller: _roomSearchController,
                decoration: InputDecoration(
                  hintText: backend.selectedSpaceId == null
                      ? 'Search direct messages and groups'
                      : 'Search rooms',
                  prefixIcon: const Icon(Icons.search, size: 17),
                  suffixIcon: _roomQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear room search',
                          onPressed: () {
                            _roomSearchController.clear();
                            setState(() => _roomQuery = '');
                          },
                          icon: const Icon(Icons.close, size: 15),
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
                onChanged: (value) => setState(() => _roomQuery = value),
              ),
            ),
          ),
          Expanded(
            child: visibleRooms.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty ? 'No joined rooms' : 'No matching rooms',
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.symmetric(
                      vertical: _densityBetween(
                        backend.preferences.compactness,
                        roomy: 8,
                        compact: 3,
                      ),
                    ),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              child: Material(
                color: context.deltiecord.rail,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => showOwnProfile(context, backend),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 36,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: ClipOval(
                                  child: backend.profileAvatarBytes == null
                                      ? ColoredBox(
                                          color: context.deltiecord.elevated,
                                          child: const Icon(
                                            Icons.person,
                                            size: 19,
                                          ),
                                        )
                                      : Image.memory(
                                          backend.profileAvatarBytes!,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                              Positioned(
                                left: -1,
                                bottom: -1,
                                child: Container(
                                  key: ValueKey(
                                    'current-user-presence-'
                                    '${backend.profilePresence.name}',
                                  ),
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: switch (backend.profilePresence) {
                                      UserPresence.online => const Color(
                                        0xff43b581,
                                      ),
                                      UserPresence.away => const Color(
                                        0xffffc857,
                                      ),
                                      UserPresence.offline => const Color(
                                        0xff747680,
                                      ),
                                    },
                                    border: Border.all(
                                      color: context.deltiecord.rail,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                backend.profileDisplayName ??
                                    backend.userId
                                        ?.split(':')
                                        .first
                                        .replaceFirst('@', '') ??
                                    'Matrix account',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (backend.profileStatusMessage
                                  case final status?)
                                Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.deltiecord.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox.square(
                          dimension: 32,
                          child: IconButton(
                            tooltip: backend.voiceMuted ? 'Unmute' : 'Mute',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                backend.setVoiceMuted(!backend.voiceMuted),
                            icon: Icon(
                              backend.voiceMuted ? Icons.mic_off : Icons.mic,
                              size: 18,
                            ),
                          ),
                        ),
                        SizedBox.square(
                          dimension: 32,
                          child: IconButton(
                            tooltip: backend.voiceDeafened
                                ? 'Undeafen'
                                : 'Deafen',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => backend.setVoiceDeafened(
                              !backend.voiceDeafened,
                            ),
                            icon: Icon(
                              backend.voiceDeafened
                                  ? Icons.headset_off
                                  : Icons.headphones,
                              size: 18,
                            ),
                          ),
                        ),
                        SizedBox.square(
                          dimension: 32,
                          child: IconButton(
                            tooltip: 'Settings',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                showDeltiecordSettings(context, backend),
                            icon: const Icon(Icons.settings_outlined, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartDirectMessageDialog extends StatefulWidget {
  const _StartDirectMessageDialog();

  @override
  State<_StartDirectMessageDialog> createState() =>
      _StartDirectMessageDialogState();
}

class _StartDirectMessageDialogState extends State<_StartDirectMessageDialog> {
  final _userIdController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_userIdController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start direct message'),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('new-direct-message-id'),
          controller: _userIdController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Matrix ID',
            hintText: '@person:example.org',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Message')),
      ],
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
      style: TextStyle(
        color: context.deltiecord.muted,
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
    final compactness = backend.preferences.compactness;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity(vertical: -1 - (compactness * 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      minVerticalPadding: 0,
      selected: backend.selectedRoom?.id == room.id,
      leading: _RoomIcon(room: room, size: 26),
      title: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: room.isVoice
          ? participantCount == 0
                ? null
                : Text('$participantCount connected')
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
          constraints: BoxConstraints(
            minHeight: _densityBetween(
              backend.preferences.compactness,
              roomy: 62,
              compact: 48,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              _densityBetween(
                backend.preferences.compactness,
                roomy: 6,
                compact: 3,
              ),
              10,
              _densityBetween(
                backend.preferences.compactness,
                roomy: 6,
                compact: 3,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _RoomIcon(room: room, size: 40, showPresence: room.isDirect),
                const SizedBox(width: 10),
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
                      SizedBox(
                        height: _densityBetween(
                          backend.preferences.compactness,
                          roomy: 6,
                          compact: 3,
                        ),
                      ),
                      Text(
                        room.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.deltiecord.muted,
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
              backgroundColor: context.deltiecord.elevated,
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
                  border: Border.all(color: context.deltiecord.panel, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
