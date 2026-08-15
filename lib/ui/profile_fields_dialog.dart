import 'package:flutter/material.dart';

import '../models/chat_models.dart';

typedef ProfileFieldsResult = ({String bio, String pronouns, String timezone});

class ProfileFieldsDialog extends StatefulWidget {
  const ProfileFieldsDialog({required this.profile, super.key});

  final UserProfileSummary profile;

  @override
  State<ProfileFieldsDialog> createState() => _ProfileFieldsDialogState();
}

class _ProfileFieldsDialogState extends State<ProfileFieldsDialog> {
  late final _bio = TextEditingController(text: widget.profile.bio);
  late final _pronouns = TextEditingController(text: widget.profile.pronouns);
  late final _timezone = TextEditingController(text: widget.profile.timezone);

  @override
  void dispose() {
    _bio.dispose();
    _pronouns.dispose();
    _timezone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Public profile details'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.profile.extensibleFieldsSupported)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'This homeserver may not support extensible profile fields. '
                'Saving can be rejected without affecting your basic profile.',
              ),
            ),
          TextField(
            controller: _bio,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Bio / about',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pronouns,
            decoration: const InputDecoration(
              labelText: 'Pronouns',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _timezone,
            decoration: const InputDecoration(
              labelText: 'Timezone (for example Europe/Amsterdam)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop((
          bio: _bio.text.trim(),
          pronouns: _pronouns.text.trim(),
          timezone: _timezone.text.trim(),
        )),
        child: const Text('Save'),
      ),
    ],
  );
}
