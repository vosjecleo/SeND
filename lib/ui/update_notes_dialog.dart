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
            '• Click or tap your own profile status to edit it\n\n'
            '• Add one Unicode or custom pack emoji to your status\n\n'
            '• Keep your emoji beside your game, app, or music\n\n'
            '• Fix saved status text disappearing during presence updates',
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
