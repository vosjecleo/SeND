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
            '• Smaller round status indicators with wider outlines\n\n'
            '• Offline ring kept; mobile phone indicator unchanged\n\n'
            '• Reply avatars now appear before the name and quoted text\n\n'
            '• Reply previews update without sending a message or reloading',
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
