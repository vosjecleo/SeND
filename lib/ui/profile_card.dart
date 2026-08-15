import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import '../services/timezone_catalog.dart';
import 'deltiecord_theme.dart';

class DeltiecordProfileCard extends StatelessWidget {
  const DeltiecordProfileCard({
    required this.profile,
    this.onEdit,
    this.onMessage,
    this.onBlock,
    this.blocked = false,
    this.preview = false,
    super.key,
  });

  final UserProfileSummary profile;
  final VoidCallback? onEdit;
  final VoidCallback? onMessage;
  final VoidCallback? onBlock;
  final bool blocked;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final palette = context.deltiecord;
    final accent = Theme.of(context).colorScheme.primary;
    final timezone = profile.timezone;
    return Container(
      key: const Key('profile-card'),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.divider),
        borderRadius: BorderRadius.circular(5),
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 18, spreadRadius: 2),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  bottom: 60,
                  child: profile.bannerBytes == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accent.withValues(alpha: 0.72),
                                palette.rail,
                              ],
                            ),
                          ),
                        )
                      : Image.memory(
                          profile.bannerBytes!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
                Positioned(
                  left: 30,
                  bottom: 0,
                  child: Container(
                    width: 124,
                    height: 124,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.elevated,
                      border: Border.all(color: palette.surface, width: 7),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: profile.avatarBytes == null
                        ? Center(
                            child: Text(
                              profile.displayName.characters.firstOrNull
                                      ?.toUpperCase() ??
                                  '?',
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : Image.memory(
                            profile.avatarBytes!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
                Positioned(
                  left: 132,
                  bottom: 12,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _presenceColour(profile.presence),
                      border: Border.all(color: palette.surface, width: 4),
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: palette.elevated,
                      border: Border.all(color: palette.divider),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _presenceColour(profile.presence),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_presenceLabel(profile.presence)),
                      ],
                    ),
                  ),
                ),
                if (onEdit != null)
                  Positioned(
                    right: 16,
                    top: 14,
                    child: IconButton.filledTonal(
                      tooltip: 'Edit profile',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 4, 30, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      profile.displayName,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (profile.pronouns?.trim().isNotEmpty == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(profile.pronouns!),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        profile.userId,
                        style: TextStyle(color: palette.muted, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy Matrix ID',
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: profile.userId),
                      ),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                    ),
                  ],
                ),
                if (timezone?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${TimezoneCatalog.offsetLabel(timezone)}  •  '
                        '${TimezoneCatalog.localTimeLabel(timezone)}',
                        style: TextStyle(color: palette.muted),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: palette.background,
                    border: Border.all(color: palette.divider),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_outline, size: 19),
                          SizedBox(width: 8),
                          Text(
                            'About me',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        profile.bio?.trim().isNotEmpty == true
                            ? profile.bio!
                            : preview
                            ? 'Your bio preview will appear here.'
                            : 'No bio provided.',
                      ),
                    ],
                  ),
                ),
                if (onMessage != null || onBlock != null) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (onMessage != null)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onMessage,
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Message'),
                          ),
                        ),
                      if (onMessage != null && onBlock != null)
                        const SizedBox(width: 10),
                      if (onBlock != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onBlock,
                            icon: Icon(blocked ? Icons.undo : Icons.block),
                            label: Text(blocked ? 'Unblock' : 'Block'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _presenceColour(UserPresence presence) => switch (presence) {
    UserPresence.online => const Color(0xff23d887),
    UserPresence.away => const Color(0xffffc857),
    UserPresence.offline => const Color(0xff747680),
  };

  String _presenceLabel(UserPresence presence) => switch (presence) {
    UserPresence.online => 'Online',
    UserPresence.away => 'Away',
    UserPresence.offline => 'Offline',
  };
}
