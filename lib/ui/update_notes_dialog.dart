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
            '• Forward messages and whole photo galleries\n\n'
            '• GIF favourites, more categories and infinite scrolling\n\n'
            '• Faster avatars and profile loading\n\n'
            '• Clearer settings and server controls\n\n'
            '• Mobile keyboard and notification fixes\n\n'
            '• Mobile online indicators, with a Privacy switch\n\n'
            '• Security fixes for encryption, media and push notifications',
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
