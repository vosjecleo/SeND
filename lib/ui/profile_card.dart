import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import '../services/timezone_catalog.dart';
import 'deltiecord_theme.dart';
import 'json_theme.dart';

class DeltiecordProfileCard extends StatelessWidget {
  const DeltiecordProfileCard({
    required this.profile,
    this.onEdit,
    this.onClose,
    this.onMessage,
    this.onBlock,
    this.blocked = false,
    this.preview = false,
    super.key,
  });

  final UserProfileSummary profile;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;
  final VoidCallback? onMessage;
  final VoidCallback? onBlock;
  final bool blocked;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final palette = context.deltiecord;
    final accent = Color(
      profile.profileColor ?? Theme.of(context).colorScheme.primary.toARGB32(),
    );
    final secondaryAccent = Color(
      profile.profileColorSecondary ??
          Color.lerp(accent, palette.rail, 0.62)!.toARGB32(),
    );
    final gradientTop = Color.alphaBlend(
      accent.withValues(alpha: 0.42),
      palette.surface,
    );
    final gradientBottom = Color.alphaBlend(
      secondaryAccent.withValues(alpha: 0.48),
      palette.surface,
    );
    final timezone = profile.timezone;
    return Container(
      key: const Key('profile-card'),
      foregroundDecoration: BoxDecoration(
        borderRadius: DeltiecordCorners.borderRadius,
        border: Border.all(color: accent.withValues(alpha: .8), width: 1.25),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [gradientTop, gradientBottom],
        ),
        borderRadius: DeltiecordCorners.borderRadius,
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 18, spreadRadius: 2),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileHeader(
            profile: profile,
            accent: accent,
            secondaryAccent: secondaryAccent,
            onEdit: onEdit,
            onClose: onClose,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 4, 30, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        '${profile.userId}${profile.pronouns?.trim().isNotEmpty == true ? '  •  ${profile.pronouns}' : ''}',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: DeltiecordTypeScale.normal,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy Matrix ID',
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: profile.userId),
                      ),
                      icon: const ThemeIcon(Icons.copy_outlined, size: 18),
                    ),
                  ],
                ),
                if (profile.bio?.trim().isNotEmpty == true || preview) ...[
                  const SizedBox(height: 18),
                  Text(
                    profile.bio?.trim().isNotEmpty == true
                        ? profile.bio!
                        : 'Your bio preview will appear here.',
                    style: const TextStyle(height: 1.4),
                  ),
                ],
                if (timezone?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const ThemeIcon(Icons.schedule, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${TimezoneCatalog.offsetLabel(timezone)}  •  ${TimezoneCatalog.localTimeLabel(timezone)} local time',
                          style: TextStyle(color: palette.muted),
                        ),
                      ),
                    ],
                  ),
                ],
                if (onMessage != null || onBlock != null) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (onMessage != null)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onMessage,
                            icon: const ThemeIcon(Icons.chat_bubble_outline),
                            label: const Text('Message'),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: deltiecordContrastingForeground(
                                accent,
                              ),
                            ),
                          ),
                        ),
                      if (onMessage != null && onBlock != null)
                        const SizedBox(width: 10),
                      if (onBlock != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onBlock,
                            icon: ThemeIcon(blocked ? Icons.undo : Icons.block),
                            label: Text(blocked ? 'Unblock' : 'Block'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
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
}

class ProfileStatusBubble extends StatelessWidget {
  const ProfileStatusBubble({
    required this.status,
    required this.accent,
    this.expanded = false,
    super.key,
  });

  final String status;
  final Color accent;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final fill = Color.alphaBlend(
      accent.withValues(alpha: .12),
      context.deltiecord.elevated,
    );
    return Tooltip(
      message: status,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -5,
            top: 10,
            child: Transform.rotate(
              angle: .785398,
              child: SizedBox.square(
                dimension: 12,
                child: ColoredBox(color: fill),
              ),
            ),
          ),
          Container(
            width: expanded ? double.infinity : null,
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: .18)),
            ),
            child: Text(
              status.replaceAll(RegExp(r'\s+'), ' ').trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.accent,
    required this.secondaryAccent,
    required this.onEdit,
    required this.onClose,
  });

  final UserProfileSummary profile;
  final Color accent;
  final Color secondaryAccent;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.deltiecord;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bannerHeight = (constraints.maxWidth / 3).clamp(180.0, 260.0);
        return SizedBox(
          height: bannerHeight + 60,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: bannerHeight,
                child: profile.bannerBytes == null
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: 0.72),
                              secondaryAccent.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                      )
                    : Image.memory(
                        profile.bannerBytes!,
                        fit: BoxFit.cover,
                        cacheWidth: 1440,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.high,
                      ),
              ),
              Positioned(
                left: 30,
                bottom: 0,
                child: Container(
                  width: 124,
                  height: 124,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    shape:
                        Theme.of(
                              context,
                            ).extension<ThemeChrome>()?.glassAvatars ==
                            true
                        ? BoxShape.rectangle
                        : BoxShape.circle,
                    borderRadius:
                        Theme.of(
                              context,
                            ).extension<ThemeChrome>()?.glassAvatars ==
                            true
                        ? BorderRadius.circular(10)
                        : null,
                    color: palette.surface,
                  ),
                  child: ThemeAvatarClip(
                    clipBehavior: Clip.antiAlias,
                    child: ColoredBox(
                      color: palette.elevated,
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
                              cacheWidth: 256,
                              cacheHeight: 256,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.high,
                            ),
                    ),
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
                    color: _profilePresenceColour(profile.presence),
                    border: Border.all(color: palette.surface, width: 4),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                left: 168,
                bottom: 14,
                child: profile.statusMessage?.trim().isNotEmpty == true
                    ? ProfileStatusBubble(
                        status: profile.statusMessage!,
                        accent: accent,
                        expanded: true,
                      )
                    : Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: palette.elevated,
                            borderRadius: DeltiecordCorners.borderRadius,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _profilePresenceColour(
                                    profile.presence,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(_profilePresenceLabel(profile.presence)),
                            ],
                          ),
                        ),
                      ),
              ),
              if (onEdit != null || onClose != null)
                Positioned(
                  right: 16,
                  top: 14,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onEdit != null)
                        IconButton.filledTonal(
                          tooltip: 'Edit profile',
                          onPressed: onEdit,
                          icon: const ThemeIcon(Icons.edit_outlined),
                        ),
                      if (onEdit != null && onClose != null)
                        const SizedBox(width: 8),
                      if (onClose != null)
                        IconButton.filledTonal(
                          key: const Key('profile-close-button'),
                          tooltip: 'Close profile',
                          onPressed: onClose,
                          icon: const ThemeIcon(Icons.close),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Color _profilePresenceColour(UserPresence presence) => switch (presence) {
  UserPresence.online => const Color(0xff23d887),
  UserPresence.away => const Color(0xffffc857),
  UserPresence.doNotDisturb => const Color(0xffe5484d),
  UserPresence.offline => const Color(0xff747680),
};

String _profilePresenceLabel(UserPresence presence) => switch (presence) {
  UserPresence.online => 'Online',
  UserPresence.away => 'Away',
  UserPresence.doNotDisturb => 'Do not disturb',
  UserPresence.offline => 'Offline',
};
