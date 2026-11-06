import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

Future<void> deleteMessageGroup(
  BuildContext context,
  ChatBackend backend,
  List<ChatMessage> messages,
) async {
  final group = {
    for (final message in messages) message.id: message,
  }.values.toList();
  if (group.isEmpty || group.any((m) => !m.own || m.pending || m.failed)) {
    return;
  }
  final expected = group.first.attachment?.gallery?.count ?? group.length;
  if (expected != group.length) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Load the whole gallery before deleting it.'),
      ),
    );
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(group.length > 1 ? 'Delete gallery?' : 'Delete message?'),
      content: Text(
        group.length > 1
            ? 'Delete all ${group.length} messages in this gallery for everyone?'
            : 'Delete this message for everyone?',
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
  if (confirmed != true) return;
  var deleted = 0;
  try {
    for (final message in group) {
      await backend.redactMessage(message.id);
      deleted++;
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            deleted == 0
                ? 'Could not delete the message. Check your connection and permissions.'
                : '$deleted of ${group.length} messages deleted. Try deleting the remaining messages again.',
          ),
        ),
      );
    }
  }
}
