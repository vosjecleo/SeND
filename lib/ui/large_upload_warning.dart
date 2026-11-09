import 'package:flutter/material.dart';
import '../models/chat_models.dart';

Future<bool> confirmLargeUpload(
  BuildContext context,
  List<AttachmentDraft> files,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Large upload'),
        content: SingleChildScrollView(
          child: Text(
            '${files.map((file) => '${file.name} (${(file.bytes.length / (1024 * 1024)).toStringAsFixed(1)} MiB)').join('\n')}\n\n'
            'These files are over 128 MiB. Sending them may use a lot of data.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send anyway'),
          ),
        ],
      ),
    ) ??
    false;
