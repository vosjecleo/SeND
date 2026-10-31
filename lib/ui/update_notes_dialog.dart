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
            '• Smoother message sending and media progress\n\n'
            '• Composer wrapping, padding and editing fixes\n\n'
            '• Clearer emoji completion and matching fonts\n\n'
            '• Better Archive gestures and compact desktop navigation\n\n'
            '• Aligned replies, avatars and typing indicators\n\n'
            '• Clearer call controls and smoother sound cues\n\n'
            '• Safer browser storage and signed updates\n\n'
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
