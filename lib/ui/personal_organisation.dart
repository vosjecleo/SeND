import 'dart:math';
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/space_organisation.dart';
import 'hold_move_draggable.dart';
import 'lifecycle_memory_image.dart';
import 'profile_watch.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

Future<void> showPersonalOrganisation(
  BuildContext context,
  ChatBackend backend,
) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    child: SizedBox(
      width: 520,
      height: 620,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chats and spaces'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: backend,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PersonalOrganisationPanel(backend: backend),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _save(BuildContext context, Future<void> action) async {
  try {
    await action;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save this change. Check device storage and retry.',
          ),
        ),
      );
    }
  }
}

class PersonalOrganisationPanel extends StatelessWidget {
  const PersonalOrganisationPanel({required this.backend, super.key});
  final ChatBackend backend;
  Future<void> _folder(
    BuildContext context, {
    String? id,
    String? initial,
  }) async {
    final name = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(id == null ? 'New space folder' : 'Rename folder'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    if (value == null || value.isEmpty || !context.mounted) return;
    final key =
        id ??
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    await _save(context, backend.personalData!.set('folder:$key', value));
  }

  @override
  Widget build(BuildContext context) {
    final data = backend.personalData;
    if (data == null) return const Text('Personal settings are loading.');
    final spaces = backend.spaces;
    final folders = data.folders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.warning case final warning?) Text(warning),
        Text('Space bar', style: Theme.of(context).textTheme.titleMedium),
        const Text(
          'Drag to reorder. Folders and order follow your account across devices.',
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: spaces.length,
          onReorderItem: (from, to) {
            final ids = spaces.map((s) => s.id).toList();
            ids.insert(to, ids.removeAt(from));
            _save(context, data.set('spaceOrder', ids));
          },
          itemBuilder: (context, index) {
            final space = spaces[index];
            return ListTile(
              key: ValueKey('organise-${space.id}'),
              title: Text(space.name),
              contentPadding: EdgeInsets.zero,
              subtitle: DropdownButton<String>(
                isExpanded: true,
                value: data.folderFor(space.id) ?? '',
                items: [
                  const DropdownMenuItem(value: '', child: Text('No folder')),
                  for (final f in folders.entries)
                    DropdownMenuItem(value: f.key, child: Text(f.value)),
                ],
                onChanged: (id) => _save(
                  context,
                  data.set(
                    'folderOf:${space.id}',
                    id?.isEmpty == true ? null : id,
                  ),
                ),
              ),
            );
          },
        ),
        OutlinedButton.icon(
          onPressed: () => _folder(context),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('New folder'),
        ),
        for (final folder in folders.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(folder.value),
            leading: const Icon(Icons.folder_outlined),
            onTap: () =>
                _folder(context, id: folder.key, initial: folder.value),
            trailing: IconButton(
              tooltip: 'Remove folder; keep spaces',
              icon: const Icon(Icons.folder_off_outlined),
              onPressed: () =>
                  _save(context, data.set('folder:${folder.key}', null)),
            ),
          ),
        const Divider(height: 28),
        Text('Archived chats', style: Theme.of(context).textTheme.titleMedium),
        const Text(
          'Archived chats stay here until restored. Their notification settings stay the same.',
        ),
        if (backend.archivedRooms.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No archived chats.'),
          ),
        for (final room in backend.archivedRooms)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(room.name),
            onTap: () async {
              backend.selectSpace(null);
              await backend.selectRoom(room.id);
              if (context.mounted) Navigator.pop(context);
            },
            subtitle: room.unreadCount > 0
                ? Text('${room.unreadCount} unread')
                : null,
            trailing: IconButton(
              tooltip: 'Restore chat',
              icon: const Icon(Icons.unarchive_outlined),
              onPressed: () =>
                  _save(context, backend.archiveRoom(room.id, false)),
            ),
          ),
      ],
    );
  }
}

class SpaceFolderRail extends StatefulWidget {
  const SpaceFolderRail({
    required this.backend,
    required this.itemBuilder,
    this.onSpaceMenu,
    super.key,
  });
  final ChatBackend backend;
  final Widget Function(SpaceSummary) itemBuilder;
  final void Function(SpaceSummary, Offset)? onSpaceMenu;
  @override
  State<SpaceFolderRail> createState() => _SpaceFolderRailState();
}

class _SpaceFolderRailState extends State<SpaceFolderRail> {
  final _open = <String>{};
  final _hover = <String, SpaceDropPosition>{};
  final _starts = <int, ({Timer timer, Offset position})>{};
  final _held = <int>{};
  final _moved = <int>{};
  String? _dragging;
  bool _saving = false;
  @override
  void dispose() {
    for (final start in _starts.values) {
      start.timer.cancel();
    }
    super.dispose();
  }

  Future<void> _folderMenu(String id, Offset position) async {
    final data = widget.backend.personalData;
    if (data == null) return;
    final size = MediaQuery.sizeOf(context);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & size,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('Rename folder')),
        PopupMenuItem(
          value: 'ungroup',
          child: Text('Remove folder; keep spaces'),
        ),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'ungroup') {
      await _save(context, data.set('folder:$id', null));
      return;
    }
    final controller = TextEditingController(text: data.folders[id]);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(
          controller: controller,
          maxLength: 40,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty && mounted) {
      await _save(context, data.set('folder:$id', name));
    }
  }

  SpaceDropPosition _position(BuildContext target, Offset point) {
    final box = target.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return SpaceDropPosition.inside;
    final y = box.globalToLocal(point).dy / box.size.height;
    return y < .22
        ? SpaceDropPosition.before
        : y > .78
        ? SpaceDropPosition.after
        : SpaceDropPosition.inside;
  }

  Future<void> _drop(
    SpaceDragItem source,
    SpaceDragItem target,
    SpaceDropPosition position,
  ) async {
    final data = widget.backend.personalData;
    if (data == null || _saving) return;
    _saving = true;
    try {
      final folder = await dropSpace(
        data,
        widget.backend.spaces.map((s) => s.id).toList(),
        source,
        target,
        position,
      );
      if (mounted) {
        setState(() {
          if (folder != null) _open.add(folder);
          _hover.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the space layout.')),
        );
      }
    } finally {
      _saving = false;
    }
  }

  Widget _target(
    SpaceDragItem item,
    Widget child,
    void Function(Offset)? menu,
  ) => Builder(
    builder: (targetContext) => DragTarget<SpaceDragItem>(
      key: ValueKey('space-drop-${item.key}'),
      onWillAcceptWithDetails: (details) =>
          widget.backend.personalData != null &&
          details.data.key != item.key &&
          !_saving,
      onMove: (details) {
        final position = _position(targetContext, details.offset);
        if (_hover[item.key] != position) {
          setState(() => _hover[item.key] = position);
        }
      },
      onLeave: (_) {
        if (mounted) setState(() => _hover.remove(item.key));
      },
      onAcceptWithDetails: (details) =>
          _drop(details.data, item, _position(targetContext, details.offset)),
      builder: (context, candidates, rejected) {
        final position = candidates.isEmpty
            ? null
            : _hover[item.key] ?? SpaceDropPosition.inside;
        final highlighted = position == SpaceDropPosition.inside;
        final contents = Stack(
          children: [
            child,
            if (position != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: highlighted
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            )
                          : Border(
                              top: position == SpaceDropPosition.before
                                  ? BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      width: 3,
                                    )
                                  : BorderSide.none,
                              bottom: position == SpaceDropPosition.after
                                  ? BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      width: 3,
                                    )
                                  : BorderSide.none,
                            ),
                      borderRadius: highlighted
                          ? BorderRadius.circular(14)
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        );
        return Listener(
          onPointerDown: (event) {
            if (event.buttons == kPrimaryButton) {
              _starts[event.pointer] = (
                timer: Timer(
                  const Duration(milliseconds: 500),
                  () => _held.add(event.pointer),
                ),
                position: event.position,
              );
            }
          },
          onPointerMove: (event) {
            final start = _starts[event.pointer];
            if (start != null &&
                (event.position - start.position).distance > kTouchSlop) {
              _moved.add(event.pointer);
            }
          },
          onPointerCancel: (event) {
            _starts.remove(event.pointer)?.timer.cancel();
            _held.remove(event.pointer);
            _moved.remove(event.pointer);
          },
          onPointerUp: (event) {
            final start = _starts.remove(event.pointer),
                moved = _moved.remove(event.pointer);
            start?.timer.cancel();
            final held = _held.remove(event.pointer);
            if (start != null && !moved && _dragging == null && held) {
              menu?.call(event.position);
            }
          },
          child: GestureDetector(
            onSecondaryTapDown: menu == null
                ? null
                : (details) => menu(details.globalPosition),
            child: HoldMoveDraggable<SpaceDragItem>(
              key: ValueKey('space-drag-${item.key}'),
              data: item,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(width: 64, child: IgnorePointer(child: child)),
              ),
              childWhenDragging: Opacity(opacity: .3, child: contents),
              onDragStarted: () {
                _dragging = item.key;
                HapticFeedback.selectionClick();
              },
              onDragEnd: (_) {
                _dragging = null;
              },
              child: contents,
            ),
          ),
        );
      },
    ),
  );

  Widget _server(SpaceSummary space, {String? folder}) {
    return _target(
      SpaceDragItem.space(space.id, parentFolder: folder),
      ProfileWatch(
        backend: widget.backend,
        id: space.id,
        child: widget.itemBuilder(space),
      ),
      widget.onSpaceMenu == null
          ? null
          : (point) => widget.onSpaceMenu!(space, point),
    );
  }

  Widget _folder(String id, List<SpaceSummary> members) {
    final data = widget.backend.personalData!;
    final size = MediaQuery.sizeOf(context).width < 720 ? 54.0 : 44.0;
    final selected = members.any((s) => s.id == widget.backend.selectedSpaceId);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Tooltip(
        message: '${data.folders[id] ?? 'Folder'} (${members.length})',
        triggerMode: TooltipTriggerMode.manual,
        child: InkWell(
          onTap: () => setState(() {
            if (!_open.add(id)) _open.remove(id);
          }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: GridView.count(
              crossAxisCount: 2,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
              children: [
                for (final space in members.take(4))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: space.avatarBytes == null
                        ? Center(
                            child: Text(
                              space.name.characters.firstOrNull ?? '?',
                            ),
                          )
                        : LifecycleMemoryImage(
                            bytes: space.avatarBytes!,
                            animated: false,
                            autoplay: false,
                            decodeWidth: 32,
                            fit: BoxFit.cover,
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return _target(
      SpaceDragItem.folder(id),
      child,
      (point) => _folderMenu(id, point),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend,
        data = backend.personalData,
        shown = <String>{};
    final children = <Widget>[];
    for (final space in backend.spaces) {
      final folder = data?.folderFor(space.id);
      if (folder == null) {
        children.add(_server(space));
        continue;
      }
      if (!shown.add(folder)) continue;
      final members = backend.spaces
          .where((s) => data?.folderFor(s.id) == folder)
          .toList();
      children.add(_folder(folder, members));
      if (_open.contains(folder)) {
        children.add(
          Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: members.map((s) => _server(s, folder: folder)).toList(),
            ),
          ),
        );
      }
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
