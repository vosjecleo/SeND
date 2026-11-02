import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../version.dart';

Future<void> showUpdateNotes(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog(
    title: const Text('An Update?!? Whats changed...?'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              Colors.black.withValues(alpha: .12),
              Theme.of(context).colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'SeND $deltiecordVersion, build $deltiecordBuildNumber\n\n'
            '• Fixed gaps and jumps in chat history\n\n'
            '• Reply and edit highlights, clearer links\n\n'
            '• Better emoji receipts and mobile spacing\n\n'
            '• A tidier Archive shortcut\n\n'
            '• Read-only channels no longer offer a composer\n\n'
            '• RAW images stay out of the built-in editor\n\n'
            '• Various bug fixes',
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => launchUrl(
          Uri.parse('https://github.com/VosjeCleo/SeND/blob/main/CHANGELOG.md'),
          mode: LaunchMode.externalApplication,
        ),
        child: const Text('Full log'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Okay!'),
      ),
    ],
  ),
);
