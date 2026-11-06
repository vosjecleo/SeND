import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';
import 'profile_card.dart';
import 'profile_editor_dialog.dart';
import 'settings_page_transition.dart';
import 'space_administration_panel.dart';
import 'room_access_dialog.dart';
import '../models/space_administration.dart';
import 'member_management.dart';
import 'channel_category_menu.dart';
import 'channel_join_indicator.dart';

Future<bool?> chooseSpaceEncryption(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Encrypt new channels?'),
    content: const Text(
      'Applies to new channels. Without encryption, homeserver operators can read messages. Encryption can\'t be turned off in existing encrypted channels.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('No encryption'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Enable encryption'),
      ),
    ],
  ),
);

enum _SpaceSettingsPage {
  notifications,
  serverProfile,
  basic,
  channels,
  members,
  roles,
  defaults,
  pages,
  access,
}

Future<void> showSpaceSettings(
  BuildContext context,
  ChatBackend backend,
  SpaceSummary space, {
  bool mobile = false,
  bool openServerProfile = false,
}) async {
  final content = _SpaceSettingsView(
    backend: backend,
    space: space,
    mobile: mobile,
    initialPage: openServerProfile
        ? _SpaceSettingsPage.serverProfile
        : _SpaceSettingsPage.basic,
  );
  if (mobile) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: content)));
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          Dialog(child: SizedBox(width: 920, height: 700, child: content)),
    );
  }
}

Future<bool> showSpacePages(
  BuildContext context,
  ChatBackend backend,
  String spaceId, {
  bool skipWhenEmpty = false,
}) async {
  final pages = await backend.getSpacePages(spaceId);
  if (skipWhenEmpty &&
      pages.welcome.trim().isEmpty &&
      pages.rules.trim().isEmpty) {
    return false;
  }
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 650,
        height: 620,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Welcome'),
                  Tab(text: 'Rules'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _SpacePageText(
                      text: pages.welcome,
                      empty: 'This Space has no welcome page yet.',
                    ),
                    _SpacePageText(
                      text: pages.rules,
                      empty: 'This Space has no rules page yet.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return true;
}

class _SpacePageText extends StatelessWidget {
  const _SpacePageText({required this.text, required this.empty});

  final String text;
  final String empty;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: SelectableText(text.trim().isEmpty ? empty : text),
  );
}

class _SpaceSettingsView extends StatefulWidget {
  const _SpaceSettingsView({
    required this.backend,
    required this.space,
    required this.mobile,
    required this.initialPage,
  });

  final ChatBackend backend;
  final SpaceSummary space;
  final bool mobile;
  final _SpaceSettingsPage initialPage;

  @override
  State<_SpaceSettingsView> createState() => _SpaceSettingsViewState();
}

class _SpaceSettingsViewState extends State<_SpaceSettingsView> {
  late _SpaceSettingsPage _page = widget.initialPage;
  late final TextEditingController _name = TextEditingController(
    text: widget.space.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.space.topic,
  );
  final _welcome = TextEditingController();
  final _rules = TextEditingController();
  Uint8List? _spaceAvatar;
  late Uint8List? _savedAvatar = widget.space.avatarBytes;
  UserProfileSummary? _globalProfile;
  SpaceProfileOverride? _spaceProfileOverride;
  RoomNotificationMode _suggested = RoomNotificationMode.mentionsOnly;
  late bool _spaceMuted = widget.space.muted;
  bool _loading = true;
  int _loadGeneration = 0;
  bool _busy = false, _roleDirty = false;
  bool _joiningChannels = false;
  String? _error, _notice;
  String _memberQuery = '';
  int _memberLimit = 50;
  Future<Map<String, String>>? _members;
  RoomAccessSettings? _defaults;
  String _defaultAccess = 'invite';
  late bool _defaultEncryption = backend.channelEncryptionForSpace(
    widget.space.id,
  );
  bool _defaultsLoaded = false, _pagesLoaded = false, _profileLoaded = false;
  bool _removeAvatar = false;
  late String _savedName = widget.space.name,
      _savedDescription = widget.space.topic;
  String _savedWelcome = '', _savedRules = '', _savedAccess = 'invite';
  late bool _savedEncryption = _defaultEncryption;
  RoomNotificationMode _savedSuggested = RoomNotificationMode.mentionsOnly;
  Set<String> _announcements = {}, _savedAnnouncements = {};
  late bool _mobileMenu = widget.initialPage == _SpaceSettingsPage.basic;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _description, _welcome, _rules]) {
      controller.addListener(_draftChanged);
    }
    backend.addListener(_backendChanged);
    if (!_allowed(_page)) _page = _SpaceSettingsPage.notifications;
    _loadPage(_page);
    backend.refreshSpaceRooms(widget.space.id).catchError((Object _) {});
  }

  bool _can(String type) => backend.canChangeRoomState(widget.space.id, type);
  bool _allowed(_SpaceSettingsPage page) => switch (page) {
    _SpaceSettingsPage.notifications ||
    _SpaceSettingsPage.serverProfile => true,
    _SpaceSettingsPage.basic =>
      _can('m.room.name') || _can('m.room.topic') || _can('m.room.avatar'),
    _SpaceSettingsPage.channels =>
      backend.canManageSpaceChannelLayout(widget.space.id) ||
          _can('m.space.child'),
    _SpaceSettingsPage.members =>
      backend.canInviteToRoom(widget.space.id) || _can('m.room.power_levels'),
    _SpaceSettingsPage.roles => _can('m.room.power_levels'),
    _SpaceSettingsPage.defaults =>
      _can(spacePolicyEventType) || _can('net.send.channel_encryption'),
    _SpaceSettingsPage.pages => _can('net.deltiecord.space.pages'),
    _SpaceSettingsPage.access => _can('m.room.join_rules'),
  };
  bool get _dirty =>
      _roleDirty ||
      _name.text != _savedName ||
      _description.text != _savedDescription ||
      _spaceAvatar != null ||
      _removeAvatar ||
      (_pagesLoaded &&
          (_welcome.text != _savedWelcome || _rules.text != _savedRules)) ||
      (_defaultsLoaded &&
          (_defaultAccess != _savedAccess ||
              _defaultEncryption != _savedEncryption ||
              _suggested != _savedSuggested ||
              _announcements.length != _savedAnnouncements.length ||
              !_announcements.containsAll(_savedAnnouncements)));
  void _draftChanged() {
    if (mounted) setState(() {});
  }

  void _backendChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _discard() async {
    if (_busy) return false;
    if (!_dirty) return true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return false;
    _name.text = _savedName;
    _description.text = _savedDescription;
    _welcome.text = _savedWelcome;
    _rules.text = _savedRules;
    setState(() {
      _spaceAvatar = null;
      _removeAvatar = false;
      _roleDirty = false;
      _defaultAccess = _savedAccess;
      _defaultEncryption = _savedEncryption;
      _suggested = _savedSuggested;
      _announcements = {..._savedAnnouncements};
    });
    return true;
  }

  Future<void> _back() async {
    if (!await _discard() || !mounted) return;
    if (widget.mobile && !_mobileMenu) {
      setState(() => _mobileMenu = true);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _switchPage(_SpaceSettingsPage page) async {
    if (!await _discard() || !mounted) return;
    setState(() {
      _page = page;
      _mobileMenu = false;
      _error = null;
      _notice = null;
    });
    await _loadPage(page);
  }

  Future<void> _loadPage(_SpaceSettingsPage page) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (page) {
        case _SpaceSettingsPage.pages:
          if (!_pagesLoaded) {
            final pages = await backend.getSpacePages(widget.space.id);
            if (!mounted) return;
            _welcome.text = _savedWelcome = pages.welcome;
            _rules.text = _savedRules = pages.rules;
            _pagesLoaded = true;
          }
        case _SpaceSettingsPage.defaults:
          if (!_defaultsLoaded) {
            final values = await Future.wait<Object>([
              backend.getRoomAccessSettings(widget.space.id),
              backend.getSpacePages(widget.space.id),
            ]);
            if (!mounted) return;
            _defaults = values[0] as RoomAccessSettings;
            _defaultAccess = _savedAccess = _defaults!.defaultChannelAccess;
            _defaultEncryption = _savedEncryption = backend
                .channelEncryptionForSpace(widget.space.id);
            _suggested = _savedSuggested =
                (values[1] as SpacePagesSummary).suggestedNotificationMode;
            _announcements = {
              ...(values[1] as SpacePagesSummary).announcementChannelIds,
            };
            _savedAnnouncements = {..._announcements};
            _defaultsLoaded = true;
          }
        case _SpaceSettingsPage.serverProfile:
          if (!_profileLoaded) await _load();
        case _SpaceSettingsPage.members:
          _members ??= backend.getSpaceMembers(widget.space.id);
        default:
          break;
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        _error =
            'Could not load settings. Check your connection and try again.';
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _load() async {
    final userId = backend.userId;
    final values = await Future.wait<Object?>([
      backend.getSpaceProfileOverride(widget.space.id),
      if (userId != null) backend.getUserProfile(userId),
    ]);
    if (!mounted) return;
    setState(() {
      _spaceProfileOverride = values[0] as SpaceProfileOverride?;
      _globalProfile = values.length > 1
          ? values[1] as UserProfileSummary?
          : null;
      _profileLoaded = true;
    });
  }

  @override
  void dispose() {
    backend.removeListener(_backendChanged);
    _name.dispose();
    _description.dispose();
    _welcome.dispose();
    _rules.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigation = ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            widget.space.name,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
        const ListTile(dense: true, title: Text('My settings')),
        for (final page in [
          _SpaceSettingsPage.notifications,
          _SpaceSettingsPage.serverProfile,
        ])
          _navigationLink(page),
        if (_SpaceSettingsPage.values.skip(2).any(_allowed)) ...[
          const Divider(),
          const ListTile(dense: true, title: Text('Manage server')),
          for (final page in _SpaceSettingsPage.values.skip(2))
            if (_allowed(page)) _navigationLink(page),
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.close),
          title: const Text('Close'),
          onTap: _back,
        ),
      ],
    );
    final reduceMotion =
        widget.backend.preferences.reducedMotion ||
        MediaQuery.disableAnimationsOf(context);
    final pageBody = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(
                  onPressed: () => _loadPage(_page),
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        : _pageBody();
    final body = widget.mobile
        ? pageBody
        : SettingsPageTransition(
            reduceMotion: reduceMotion,
            child: KeyedSubtree(key: ValueKey(_page), child: pageBody),
          );
    if (widget.mobile) {
      return PopScope(
        canPop: _mobileMenu && !_dirty && !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                leading: IconButton(
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back),
                ),
                title: Text(_mobileMenu ? 'Space settings' : _pageLabel(_page)),
              ),
              Expanded(
                child: SettingsPageTransition(
                  reduceMotion: reduceMotion,
                  backwards: _mobileMenu,
                  child: _mobileMenu
                      ? KeyedSubtree(
                          key: const ValueKey('space-settings-menu'),
                          child: navigation,
                        )
                      : KeyedSubtree(
                          key: ValueKey('space-settings-${_page.name}'),
                          child: body,
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Row(
        children: [
          SizedBox(width: 230, child: navigation),
          VerticalDivider(width: 1, color: context.deltiecord.divider),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _pageBody() => switch (_page) {
    _SpaceSettingsPage.notifications => _notifications(),
    _SpaceSettingsPage.members => _membersPage(),
    _SpaceSettingsPage.defaults => _defaultsPage(),
    _SpaceSettingsPage.access => _section('Access & discovery', [
      FilledButton.icon(
        onPressed: () => showRoomAccessDialog(
          context,
          backend,
          widget.space.id,
          isSpace: true,
          children: [
            for (final room in backend.roomsInSpace(widget.space.id))
              AdministrationRoom(
                id: room.id,
                name: room.name,
                powerLevels: const {},
                canEdit: backend.canChangeRoomState(
                  room.id,
                  'm.room.join_rules',
                ),
              ),
          ],
        ),
        icon: const Icon(Icons.public),
        label: const Text('Who can join and find this server'),
      ),
    ]),
    _SpaceSettingsPage.basic => _basic(),
    _SpaceSettingsPage.channels => _channels(),
    _SpaceSettingsPage.roles => _roles(),
    _SpaceSettingsPage.pages => _pages(),
    _SpaceSettingsPage.serverProfile => _serverProfile(),
  };

  Widget _section(String title, List<Widget> children) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        if (_busy) const LinearProgressIndicator(),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_notice!),
          ),
        ...children,
      ],
    ),
  );

  Widget _basic() => _section('Overview', [
    OutlinedButton.icon(
      onPressed: () => showRoomAccessDialog(
        context,
        backend,
        widget.space.id,
        isSpace: true,
      ),
      icon: const Icon(Icons.public),
      label: const Text('Access and discovery'),
    ),
    Center(
      child: CircleAvatar(
        key: const Key('space-settings-avatar-preview'),
        radius: 46,
        backgroundImage: _removeAvatar || (_spaceAvatar ?? _savedAvatar) == null
            ? null
            : MemoryImage((_spaceAvatar ?? _savedAvatar)!),
        child: _removeAvatar || (_spaceAvatar ?? _savedAvatar) == null
            ? const Icon(Icons.hub_outlined, size: 36)
            : null,
      ),
    ),
    TextButton.icon(
      onPressed: _busy || !_can('m.room.avatar')
          ? null
          : () => _pickImage((bytes) {
              _spaceAvatar = bytes;
              _removeAvatar = false;
            }),
      icon: const Icon(Icons.image_outlined),
      label: const Text('Choose picture'),
    ),
    if ((_spaceAvatar ?? _savedAvatar) != null && !_removeAvatar)
      TextButton(
        onPressed: _busy || !_can('m.room.avatar')
            ? null
            : () => setState(() => _removeAvatar = true),
        child: const Text('Remove picture'),
      ),
    TextField(
      key: const Key('space-settings-name'),
      enabled: !_busy && _can('m.room.name'),
      controller: _name,
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    const SizedBox(height: 12),
    TextField(
      key: const Key('space-settings-topic'),
      enabled: !_busy && _can('m.room.topic'),
      controller: _description,
      maxLines: 4,
      decoration: const InputDecoration(labelText: 'Description'),
    ),
    const SizedBox(height: 12),
    Text(
      '${backend.roomsInSpace(widget.space.id).where((room) => !room.isVoice).length} text rooms  •  '
      '${backend.roomsInSpace(widget.space.id).where((room) => room.isVoice).length} voice rooms  •  '
      '${backend.categoriesInSpace(widget.space.id).length} categories',
      key: const Key('space-settings-room-summary'),
      style: TextStyle(color: context.deltiecord.muted),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Clipboard.setData(
          ClipboardData(text: 'https://matrix.to/#/${widget.space.id}'),
        ),
        icon: const Icon(Icons.link),
        label: const Text('Copy Space link'),
      ),
    ),
    TextButton.icon(
      onPressed: () => _switchPage(_SpaceSettingsPage.roles),
      icon: const Icon(Icons.admin_panel_settings_outlined),
      label: const Text('Manage roles and permissions'),
    ),
    const SizedBox(height: 18),
    FilledButton(
      onPressed: _busy || !_dirty || _name.text.trim().isEmpty
          ? null
          : _saveBasic,
      child: const Text('Save changes'),
    ),
  ]);

  Widget _channels() {
    final rooms = {
      for (final room in backend.roomsInSpace(widget.space.id)) room.id: room,
    };
    final categories = backend.categoriesInSpace(widget.space.id);
    final categorized = categories
        .expand((category) => category.roomIds)
        .toSet();
    final loose = backend
        .roomsInSpace(widget.space.id)
        .where((room) => !categorized.contains(room.id))
        .toList();
    final canManage = backend.canManageSpaceChannelLayout(widget.space.id);
    return _section('Channels', [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy || !_can('m.space.child') ? null : _createChannel,
            icon: const Icon(Icons.add),
            label: const Text('Create channel'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || !canManage ? null : _createCategory,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Create category'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (loose.isNotEmpty) ...[
        const ListTile(title: Text('Uncategorised')),
        for (var index = 0; index < loose.length; index++)
          _draggableRoomTile(
            loose[index],
            ChannelCategorySummary(
              id: '',
              name: 'Uncategorised',
              roomIds: loose.map((room) => room.id).toList(),
            ),
            index,
            canManage,
          ),
      ],
      for (
        var categoryIndex = 0;
        categoryIndex < categories.length;
        categoryIndex++
      ) ...[
        DragTarget<String>(
          onWillAcceptWithDetails: (details) =>
              canManage && details.data.startsWith('category:'),
          onAcceptWithDetails: (details) => _moveCategory(
            details.data.substring('category:'.length),
            categoryIndex,
          ),
          builder: (context, categoryCandidates, _) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: categoryCandidates.isEmpty
                  ? context.deltiecord.panel
                  : context.deltiecord.hover,
              borderRadius: DeltiecordCorners.borderRadius,
            ),
            child: DragTarget<String>(
              onWillAcceptWithDetails: (details) =>
                  canManage && details.data.startsWith('room:'),
              onAcceptWithDetails: (details) => _moveChannel(
                details.data.substring('room:'.length),
                categoryId: categories[categoryIndex].id,
              ),
              builder: (context, roomCandidates, _) => Column(
                children: [
                  _draggableCategoryHeader(
                    categories,
                    categoryIndex,
                    canManage,
                  ),
                  for (
                    var roomIndex = 0;
                    roomIndex < categories[categoryIndex].roomIds.length;
                    roomIndex++
                  )
                    if (rooms[categories[categoryIndex].roomIds[roomIndex]]
                        case final room?)
                      _draggableRoomTile(
                        room,
                        categories[categoryIndex],
                        roomIndex,
                        canManage,
                      ),
                  if (roomCandidates.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Move to ${categories[categoryIndex].name}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _draggableCategoryHeader(
    List<ChannelCategorySummary> categories,
    int index,
    bool canManage,
  ) {
    final category = categories[index];
    final tile = ListTile(
      dense: true,
      leading: canManage ? const Icon(Icons.drag_indicator) : null,
      title: Text(
        category.name.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      trailing: Wrap(
        children: [
          if (canManage)
            IconButton(
              tooltip: 'Category options',
              icon: const Icon(Icons.more_horiz),
              onPressed: () => showChannelCategoryMenu(
                context,
                backend,
                category,
                spaceId: widget.space.id,
              ),
            ),
          IconButton(
            tooltip: 'Move category up',
            onPressed: canManage && index > 0
                ? () => _moveCategory(category.id, index - 1)
                : null,
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
          IconButton(
            tooltip: 'Move category down',
            onPressed: canManage && index < categories.length - 1
                ? () => _moveCategory(category.id, index + 1)
                : null,
            icon: const Icon(Icons.arrow_downward, size: 18),
          ),
        ],
      ),
    );
    if (!canManage) return tile;
    return LongPressDraggable<String>(
      data: 'category:${category.id}',
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: BoxDecoration(color: context.deltiecord.elevated),
            child: tile,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }

  Widget _draggableRoomTile(
    RoomSummary room,
    ChannelCategorySummary category,
    int index,
    bool canManage,
  ) {
    final tile = ChannelJoinIndicator(
      joined: room.joined,
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -3),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManage) const Icon(Icons.drag_indicator, size: 18),
            Icon(room.isVoice ? Icons.volume_up : Icons.tag, size: 18),
          ],
        ),
        title: Text(room.name),
        trailing: Wrap(
          children: [
            PopupMenuButton<String>(
              tooltip: 'Channel options',
              icon: const Icon(Icons.more_horiz, size: 18),
              onSelected: (value) async {
                if (value == 'edit') await _editChannel(room);
                if (value == 'access') {
                  if (mounted) {
                    await showRoomAccessDialog(
                      context,
                      backend,
                      room.id,
                      spaceId: widget.space.id,
                    );
                  }
                }
                if (value == 'remove') await _removeChannel(room);
              },
              itemBuilder: (_) => [
                if ([
                  'm.room.name',
                  'm.room.topic',
                  'net.deltiecord.room.presentation',
                ].any((type) => backend.canChangeRoomState(room.id, type)))
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit channel'),
                  ),
                if (backend.canChangeRoomState(room.id, 'm.room.join_rules'))
                  const PopupMenuItem(
                    value: 'access',
                    child: Text('Channel access'),
                  ),
                if (_can('m.space.child'))
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from server'),
                  ),
              ],
            ),
            IconButton(
              tooltip: 'Move up',
              onPressed: canManage && index > 0
                  ? () => _moveChannel(
                      room.id,
                      categoryId: category.id.isEmpty ? null : category.id,
                      beforeRoomId: category.roomIds[index - 1],
                    )
                  : null,
              icon: const Icon(Icons.arrow_upward, size: 17),
            ),
            IconButton(
              tooltip: 'Move down',
              onPressed: canManage && index < category.roomIds.length - 1
                  ? () => _moveChannel(
                      room.id,
                      categoryId: category.id.isEmpty ? null : category.id,
                      beforeRoomId: index + 2 < category.roomIds.length
                          ? category.roomIds[index + 2]
                          : null,
                    )
                  : null,
              icon: const Icon(Icons.arrow_downward, size: 17),
            ),
          ],
        ),
      ),
    );
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          canManage &&
          details.data.startsWith('room:') &&
          details.data != 'room:${room.id}',
      onAcceptWithDetails: (details) => _moveChannel(
        details.data.substring('room:'.length),
        categoryId: category.id.isEmpty ? null : category.id,
        beforeRoomId: room.id,
      ),
      builder: (context, candidates, _) => ColoredBox(
        color: candidates.isEmpty
            ? Colors.transparent
            : context.deltiecord.hover,
        child: tile,
      ),
    );
    if (!canManage) return target;
    return LongPressDraggable<String>(
      data: 'room:${room.id}',
      feedback: Material(
        color: context.deltiecord.elevated,
        child: SizedBox(width: 360, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: target),
      child: target,
    );
  }

  Widget _roles() => _section('Administration', [
    SpaceAdministrationPanel(
      backend: backend,
      spaceId: widget.space.id,
      onDirtyChanged: (value) {
        if (mounted) setState(() => _roleDirty = value);
      },
    ),
  ]);

  Widget _pages() => _section('Welcome & rules', [
    TextField(
      controller: _welcome,
      minLines: 4,
      maxLines: 10,
      decoration: const InputDecoration(labelText: 'Welcome page'),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _rules,
      minLines: 4,
      maxLines: 10,
      decoration: const InputDecoration(labelText: 'Rules page'),
    ),
    const SizedBox(height: 12),
    const SizedBox(height: 18),
    FilledButton(
      onPressed: _busy || !_dirty ? null : _savePages,
      child: const Text('Save pages'),
    ),
  ]);

  Widget _serverProfile() => _section('Server profile', [
    if (_globalProfile case final profile?) ...[
      DeltiecordProfileCard(profile: _effectiveServerProfile(profile)),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: () => _editServerProfile(profile),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit server profile'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _spaceProfileOverride == null
            ? null
            : () async {
                await backend.setSpaceProfileOverride(
                  SpaceProfileOverride(spaceId: widget.space.id),
                );
                await _reloadServerProfile();
              },
        icon: const Icon(Icons.restart_alt),
        label: const Text('Reset to general profile'),
      ),
    ] else
      const Center(child: CircularProgressIndicator()),
  ]);

  UserProfileSummary _effectiveServerProfile(UserProfileSummary global) {
    final override = _spaceProfileOverride;
    return UserProfileSummary(
      userId: global.userId,
      displayName: override?.nickname ?? global.displayName,
      avatarBytes: override?.avatarBytes ?? global.avatarBytes,
      bannerBytes: override?.bannerBytes ?? global.bannerBytes,
      presence: global.presence,
      bio: override?.bio ?? global.bio,
      pronouns: override?.pronouns ?? global.pronouns,
      timezone: override?.timezone ?? global.timezone,
      statusMessage: override?.statusMessage ?? global.statusMessage,
      profileColor: override?.accentColor ?? global.profileColor,
      profileColorSecondary:
          override?.accentColorSecondary ?? global.profileColorSecondary,
      voiceColor: override?.voiceColor ?? global.voiceColor,
      voiceBackgroundBytes:
          override?.voiceBackgroundBytes ?? global.voiceBackgroundBytes,
      extensibleFieldsSupported: global.extensibleFieldsSupported,
    );
  }

  Future<void> _editServerProfile(UserProfileSummary profile) async {
    final changed = await showSpaceProfileEditor(
      context,
      backend,
      profile,
      _spaceProfileOverride,
      widget.space.id,
    );
    if (changed) await _reloadServerProfile();
  }

  Future<void> _reloadServerProfile() async {
    final override = await backend.getSpaceProfileOverride(widget.space.id);
    if (mounted) setState(() => _spaceProfileOverride = override);
  }

  Future<void> _pickImage(ValueChanged<Uint8List> onPicked) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes != null && mounted) setState(() => onPicked(bytes));
  }

  Future<void> _saveBasic() => _runAction(() async {
    final name = _name.text.trim(), description = _description.text.trim();
    if (name.isEmpty) return;
    if (name != _savedName) await backend.renameRoom(widget.space.id, name);
    if (description != _savedDescription) {
      await backend.setRoomTopic(widget.space.id, description);
    }
    if (_spaceAvatar != null || _removeAvatar) {
      await backend.setRoomAvatar(
        widget.space.id,
        _removeAvatar ? null : _spaceAvatar,
      );
      _savedAvatar = _removeAvatar ? null : _spaceAvatar;
    }
    if (!mounted) return;
    setState(() {
      _savedName = name;
      _savedDescription = description;
      _spaceAvatar = null;
      _removeAvatar = false;
    });
    _name.text = name;
    _description.text = description;
  }, success: 'Server settings saved.');

  Future<void> _savePages() => _runAction(() async {
    final existing = await backend.getSpacePages(widget.space.id);
    await backend.setSpacePages(
      widget.space.id,
      SpacePagesSummary(
        welcome: _welcome.text.trim(),
        rules: _rules.text.trim(),
        suggestedNotificationMode: existing.suggestedNotificationMode,
        announcementChannelIds: existing.announcementChannelIds,
      ),
    );
    if (!mounted) return;
    setState(() {
      _savedWelcome = _welcome.text.trim();
      _savedRules = _rules.text.trim();
    });
    _welcome.text = _savedWelcome;
    _rules.text = _savedRules;
  }, success: 'Welcome and rules saved.');

  Widget _navigationLink(_SpaceSettingsPage page) => ListTile(
    selected: _page == page,
    leading: Icon(_pageIcon(page)),
    title: Text(_pageLabel(page)),
    onTap: () => _switchPage(page),
  );

  Future<void> _runAction(
    Future<void> Function() action, {
    String? success,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action();
      if (mounted && success != null) setState(() => _notice = success);
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Could not save all changes. Check your connection and permissions, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinChannels() async {
    if (_joiningChannels) return;
    setState(() {
      _joiningChannels = true;
      _notice = null;
    });
    try {
      final result = await backend.joinAvailableSpaceChannels(widget.space.id);
      if (!mounted) return;
      await backend.refreshSpaceRooms(widget.space.id);
      if (!mounted) return;
      setState(
        () => _notice = result.failed == 0
            ? 'Joined ${_channelCount(result.joined)}.'
            : 'Joined ${_channelCount(result.joined)}. ${_channelCount(result.failed)} ${result.failed == 1 ? 'needs' : 'need'} attention.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Could not join channels. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _joiningChannels = false);
    }
  }

  Widget _notifications() => _section('My notifications', [
    SwitchListTile(
      key: const Key('space-settings-muted'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Mute server'),
      subtitle: const Text('Suppress notifications from this server.'),
      value: _spaceMuted,
      onChanged: _busy
          ? null
          : (value) => _runAction(() async {
              await backend.setRoomMuted(widget.space.id, value);
              if (mounted) setState(() => _spaceMuted = value);
            }),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Automatically join accessible channels'),
      value: backend.autoJoinSpaceChannels(widget.space.id),
      onChanged: _busy
          ? null
          : (value) => _runAction(
              () => backend.setAutoJoinSpaceChannels(widget.space.id, value),
            ),
    ),
    OutlinedButton.icon(
      onPressed: _busy || _joiningChannels ? null : _joinChannels,
      icon: const Icon(Icons.playlist_add_check),
      label: Text(_joiningChannels ? 'Joining…' : 'Join available channels'),
    ),
    const Divider(height: 28),
    ExpansionTile(
      title: const Text('Channel notifications'),
      children: [
        for (final room
            in backend
                .roomsInSpace(widget.space.id)
                .where((room) => room.joined))
          ListTile(
            title: Text(room.name),
            trailing: DropdownButton<RoomNotificationMode>(
              value: room.notificationMode,
              items: [
                for (final mode in RoomNotificationMode.values)
                  DropdownMenuItem(
                    value: mode,
                    child: Text(_notificationLabel(mode)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        _runAction(
                          () => backend.setRoomNotificationMode(room.id, value),
                        );
                      }
                    },
            ),
          ),
      ],
    ),
  ]);

  Widget _defaultsPage() => _section('Joining & defaults', [
    DropdownButtonFormField<String>(
      initialValue: _defaultAccess,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Default access for new channels',
      ),
      items: const [
        DropdownMenuItem(value: 'invite', child: Text('Invite only')),
        DropdownMenuItem(
          value: 'restricted',
          child: Text('Members of this server'),
        ),
        DropdownMenuItem(value: 'public', child: Text('Anyone')),
      ],
      onChanged: _busy || !_can(spacePolicyEventType)
          ? null
          : (value) => setState(() => _defaultAccess = value!),
    ),
    const SizedBox(height: 12),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Encrypt new channels'),
      subtitle: const Text(
        'Applies to new channels. Encryption cannot be turned off in existing encrypted channels.',
      ),
      value: _defaultEncryption,
      onChanged: _busy || !_can('net.send.channel_encryption')
          ? null
          : (value) => setState(() => _defaultEncryption = value),
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<RoomNotificationMode>(
      initialValue: _suggested,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Suggested notifications'),
      items: [
        for (final mode in RoomNotificationMode.values)
          DropdownMenuItem(value: mode, child: Text(_notificationLabel(mode))),
      ],
      onChanged: _busy || !_can('net.deltiecord.space.pages')
          ? null
          : (value) => setState(() => _suggested = value!),
    ),
    ExpansionTile(
      title: const Text('Announcement channels'),
      subtitle: const Text(
        'Suggest all messages for new members. Their own choices take priority.',
      ),
      children: [
        for (final room
            in backend
                .roomsInSpace(widget.space.id)
                .where((room) => !room.isVoice))
          CheckboxListTile(
            title: Text(room.name),
            value: _announcements.contains(room.id),
            onChanged: _busy || !_can('net.deltiecord.space.pages')
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _announcements.add(room.id);
                    } else {
                      _announcements.remove(room.id);
                    }
                  }),
          ),
      ],
    ),
    const SizedBox(height: 18),
    FilledButton(
      onPressed: _busy || !_dirty
          ? null
          : () => _runAction(() async {
              if (_defaultAccess != _savedAccess) {
                final latest = await backend.getRoomAccessSettings(
                  widget.space.id,
                );
                await backend.setSpacePolicy(
                  widget.space.id,
                  defaultChannelAccess: _defaultAccess,
                  eventVisibility: latest.eventVisibility,
                );
              }
              if (_defaultEncryption != _savedEncryption) {
                await backend.setChannelEncryptionForSpace(
                  widget.space.id,
                  _defaultEncryption,
                );
              }
              if (_suggested != _savedSuggested ||
                  _announcements.length != _savedAnnouncements.length ||
                  !_announcements.containsAll(_savedAnnouncements)) {
                final pages = await backend.getSpacePages(widget.space.id);
                await backend.setSpacePages(
                  widget.space.id,
                  SpacePagesSummary(
                    welcome: pages.welcome,
                    rules: pages.rules,
                    suggestedNotificationMode: _suggested,
                    announcementChannelIds: {..._announcements},
                  ),
                );
              }
              if (mounted) {
                setState(() {
                  _savedAccess = _defaultAccess;
                  _savedEncryption = _defaultEncryption;
                  _savedSuggested = _suggested;
                  _savedAnnouncements = {..._announcements};
                });
              }
            }, success: 'Channel defaults saved.'),
      child: const Text('Save changes'),
    ),
  ]);

  Widget _membersPage() => _section('Members & invitations', [
    Wrap(
      spacing: 8,
      children: [
        if (backend.canInviteToRoom(widget.space.id))
          FilledButton.icon(
            onPressed: () => showInviteMember(
              context,
              backend,
              roomId: widget.space.id,
              server: true,
            ),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Invite to server'),
          ),
        OutlinedButton(
          onPressed: () => showBannedMembers(context, backend, widget.space.id),
          child: const Text('Banned members'),
        ),
      ],
    ),
    const SizedBox(height: 12),
    TextField(
      decoration: const InputDecoration(
        labelText: 'Search members',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: (value) => setState(() {
        _memberQuery = value.trim().toLowerCase();
        _memberLimit = 50;
      }),
    ),
    FutureBuilder<Map<String, String>>(
      future: _members,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () => setState(
              () => _members = backend.getSpaceMembers(widget.space.id),
            ),
            child: const Text('Retry loading members'),
          );
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final members = snapshot.data!.entries
            .where(
              (member) => '${member.key} ${member.value}'
                  .toLowerCase()
                  .contains(_memberQuery),
            )
            .toList();
        return Column(
          children: [
            for (final member in members.take(_memberLimit))
              ListTile(title: Text(member.value), subtitle: Text(member.key)),
            if (members.length > _memberLimit)
              TextButton(
                onPressed: () => setState(() => _memberLimit += 50),
                child: const Text('Show more'),
              ),
          ],
        );
      },
    ),
    if (_allowed(_SpaceSettingsPage.roles))
      TextButton(
        onPressed: () => _switchPage(_SpaceSettingsPage.roles),
        child: const Text('Manage roles and permissions'),
      ),
  ]);

  Future<void> _createCategory() async {
    var name = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Create category'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Category name'),
            onChanged: (value) => update(() => name = value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _runAction(
        () => backend.editSpaceCategory(
          widget.space.id,
          SpaceCategoryAction.create,
          name: name,
        ),
      );
    }
  }

  Future<void> _createChannel() async {
    var name = '', topic = '';
    var kind = RoomPresentation.text;
    var encrypted = backend.channelEncryptionForSpace(widget.space.id);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Create channel'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Channel name'),
                  onChanged: (value) => update(() => name = value.trim()),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Topic (optional)',
                  ),
                  onChanged: (value) => topic = value,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RoomPresentation>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Channel type'),
                  items: const [
                    DropdownMenuItem(
                      value: RoomPresentation.text,
                      child: Text('Text'),
                    ),
                    DropdownMenuItem(
                      value: RoomPresentation.forum,
                      child: Text('Forum'),
                    ),
                    DropdownMenuItem(
                      value: RoomPresentation.voice,
                      child: Text('Voice'),
                    ),
                  ],
                  onChanged: (value) => update(() => kind = value!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End-to-end encryption'),
                  subtitle: const Text('Cannot be disabled after creation.'),
                  value: encrypted,
                  onChanged: (value) => update(() => encrypted = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _runAction(
        () => backend.createRoomInSpace(
          widget.space.id,
          name: name,
          topic: topic,
          presentation: kind,
          encrypted: encrypted,
        ),
      );
    }
  }

  Future<void> _editChannel(RoomSummary room) async {
    var name = room.name, topic = room.topic, kind = room.presentation;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Edit channel'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: name,
                  enabled: backend.canChangeRoomState(room.id, 'm.room.name'),
                  decoration: const InputDecoration(labelText: 'Channel name'),
                  onChanged: (value) => update(() => name = value.trim()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: topic,
                  enabled: backend.canChangeRoomState(room.id, 'm.room.topic'),
                  decoration: const InputDecoration(
                    labelText: 'Topic (optional)',
                  ),
                  onChanged: (value) => topic = value.trim(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RoomPresentation>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Channel type'),
                  items: const [
                    DropdownMenuItem(
                      value: RoomPresentation.text,
                      child: Text('Text'),
                    ),
                    DropdownMenuItem(
                      value: RoomPresentation.forum,
                      child: Text('Forum'),
                    ),
                    DropdownMenuItem(
                      value: RoomPresentation.voice,
                      child: Text('Voice'),
                    ),
                  ],
                  onChanged:
                      backend.canChangeRoomState(
                        room.id,
                        'net.deltiecord.room.presentation',
                      )
                      ? (value) => update(() => kind = value!)
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _runAction(() async {
        if (name != room.name) await backend.renameRoom(room.id, name);
        if (topic != room.topic) await backend.setRoomTopic(room.id, topic);
        if (kind != room.presentation) {
          await backend.setRoomPresentation(room.id, kind);
        }
        await backend.refreshSpaceRooms(widget.space.id);
      }, success: 'Channel settings saved.');
    }
  }

  Future<void> _removeChannel(RoomSummary room) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Remove ${room.name} from this server?'),
        content: const Text(
          'Messages stay, and members do not leave the channel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _runAction(
        () => backend.removeRoomFromSpace(widget.space.id, room.id),
      );
    }
  }

  Future<void> _moveCategory(String id, int index) => backend.editSpaceCategory(
    widget.space.id,
    SpaceCategoryAction.move,
    categoryId: id,
    index: index,
  );
  Future<void> _moveChannel(
    String id, {
    String? categoryId,
    String? beforeRoomId,
  }) => backend.moveRoomWithinSpace(
    widget.space.id,
    id,
    categoryId: categoryId,
    beforeRoomId: beforeRoomId,
  );
}

String _pageLabel(_SpaceSettingsPage page) => switch (page) {
  _SpaceSettingsPage.notifications => 'My notifications',
  _SpaceSettingsPage.members => 'Members & invitations',
  _SpaceSettingsPage.defaults => 'Joining & defaults',
  _SpaceSettingsPage.access => 'Access & discovery',
  _SpaceSettingsPage.basic => 'Overview',
  _SpaceSettingsPage.channels => 'Channels',
  _SpaceSettingsPage.roles => 'Roles & permissions',
  _SpaceSettingsPage.pages => 'Welcome & rules',
  _SpaceSettingsPage.serverProfile => 'Server profile',
};

IconData _pageIcon(_SpaceSettingsPage page) => switch (page) {
  _SpaceSettingsPage.notifications => Icons.notifications_outlined,
  _SpaceSettingsPage.members => Icons.group_outlined,
  _SpaceSettingsPage.defaults => Icons.tune,
  _SpaceSettingsPage.access => Icons.public,
  _SpaceSettingsPage.basic => Icons.tune,
  _SpaceSettingsPage.channels => Icons.format_list_bulleted,
  _SpaceSettingsPage.roles => Icons.badge_outlined,
  _SpaceSettingsPage.pages => Icons.article_outlined,
  _SpaceSettingsPage.serverProfile => Icons.person_outline,
};

String _notificationLabel(RoomNotificationMode mode) => switch (mode) {
  RoomNotificationMode.allMessages => 'All messages',
  RoomNotificationMode.mentionsOnly => 'Mentions only',
  RoomNotificationMode.muted => 'Muted',
};

String _channelCount(int count) =>
    '$count ${count == 1 ? 'channel' : 'channels'}';
