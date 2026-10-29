import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

Future<void> showChannelCategoryMenu(
  BuildContext context,
  ChatBackend backend,
  ChannelCategorySummary category, {
  Offset? position,
}) async {
  final space = backend.selectedSpaceId;
  bool allowed() =>
      space != null &&
      backend.selectedSpaceId == space &&
      backend.canManageSpaceChannelLayout(space) &&
      backend.selectedSpaceCategories.any((c) => c.id == category.id);
  if (!allowed()) return;
  final index = backend.selectedSpaceCategories.indexWhere(
    (c) => c.id == category.id,
  );
  final actions = <(String, String, IconData)>[
    ('edit', 'Edit category', Icons.edit_outlined),
    ('up', 'Move up', Icons.arrow_upward),
    ('down', 'Move down', Icons.arrow_downward),
    ('delete', 'Delete category', Icons.delete_outline),
  ];
  bool enabled(String action) => switch (action) {
    'up' => index > 0,
    'down' => index >= 0 && index < backend.selectedSpaceCategories.length - 1,
    _ => true,
  };
  final action = position == null
      ? await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in actions)
                  ListTile(
                    enabled: enabled(item.$1),
                    leading: Icon(item.$3),
                    title: Text(item.$2),
                    onTap: enabled(item.$1)
                        ? () => Navigator.pop(sheet, item.$1)
                        : null,
                  ),
              ],
            ),
          ),
        )
      : await showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            position & const Size(1, 1),
            Offset.zero & MediaQuery.sizeOf(context),
          ),
          items: [
            for (final item in actions)
              PopupMenuItem(
                value: item.$1,
                enabled: enabled(item.$1),
                child: Row(
                  children: [
                    Icon(item.$3, size: 19),
                    const SizedBox(width: 10),
                    Text(item.$2),
                  ],
                ),
              ),
          ],
        );
  if (!context.mounted || action == null || !allowed()) return;
  try {
    switch (action) {
      case 'edit':
        var editedName = category.name;
        final name = await showDialog<String>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Edit category'),
            content: TextFormField(
              initialValue: category.name,
              onChanged: (value) => editedName = value,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Category name'),
              onFieldSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(dialog, value.trim());
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (editedName.trim().isNotEmpty) {
                    Navigator.pop(dialog, editedName.trim());
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (name != null && allowed()) {
          await backend.renameChannelCategory(category.id, name);
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Delete category?'),
            content: const Text(
              'Its channels will no longer have a category. No channels or messages will be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true && allowed()) {
          await backend.deleteChannelCategory(category.id);
        }
      case 'up':
        if (allowed()) {
          await backend.reorderChannelCategory(category.id, index - 1);
        }
      case 'down':
        if (allowed()) {
          await backend.reorderChannelCategory(category.id, index + 1);
        }
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update the category. Check your connection and permissions.',
          ),
        ),
      );
    }
  }
}
