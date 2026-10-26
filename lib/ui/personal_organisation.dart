import 'dart:math';
import 'package:flutter/material.dart';
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
    super.key,
  });
  final ChatBackend backend;
  final Widget Function(SpaceSummary) itemBuilder;
  @override
  State<SpaceFolderRail> createState() => _SpaceFolderRailState();
}

class _SpaceFolderRailState extends State<SpaceFolderRail> {
  final _open = <String>{};
  @override
  Widget build(BuildContext context) {
    final backend = widget.backend, data = backend.personalData;
    final shown = <String>{};
    final children = <Widget>[];
    for (final space in backend.spaces) {
      final folder = data?.folderFor(space.id);
      if (folder == null) {
        children.add(widget.itemBuilder(space));
        continue;
      }
      if (!shown.add(folder)) continue;
      final members = backend.spaces
          .where((s) => data?.folderFor(s.id) == folder)
          .toList();
      final selected = members.any((s) => s.id == backend.selectedSpaceId);
      children.add(
        Tooltip(
          message: '${data!.folders[folder]} (${members.length})',
          child: GestureDetector(
            onSecondaryTap: () => showPersonalOrganisation(context, backend),
            onLongPress: () => showPersonalOrganisation(context, backend),
            child: IconButton(
              onPressed: () => setState(() {
                if (!_open.add(folder)) _open.remove(folder);
              }),
              style: IconButton.styleFrom(
                backgroundColor: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              icon: Icon(
                _open.contains(folder)
                    ? Icons.folder_open
                    : Icons.folder_outlined,
              ),
            ),
          ),
        ),
      );
      if (_open.contains(folder)) {
        children.addAll(members.map(widget.itemBuilder));
      }
    }
    if (data != null) {
      children.add(
        IconButton(
          tooltip: 'Organise spaces and archived chats',
          onPressed: () => showPersonalOrganisation(context, backend),
          icon: const Icon(Icons.folder_copy_outlined),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
