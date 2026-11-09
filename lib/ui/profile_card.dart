import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import '../services/timezone_catalog.dart';
import 'deltiecord_theme.dart';
import 'json_theme.dart';
import 'activity_widgets.dart';
import 'lifecycle_memory_image.dart';
import 'profile_media_viewer.dart';
import 'profile_watch.dart';
import 'avatar_presence.dart';
import '../models/profile_image_geometry.dart';

class DeltiecordProfileCard extends StatelessWidget {
  const DeltiecordProfileCard({
    required this.profile,
    this.onEdit,
    this.onClose,
    this.onMessage,
    this.onBlock,
    this.blocked = false,
    this.preview = false,
    this.avatarPreview,
    this.bannerPreview,
    this.minimumHeight = 0,
    this.scrollController,
    this.scrollable = false,
    this.footer,
    this.loadImage,
    super.key,
  });

  final UserProfileSummary profile;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;
  final VoidCallback? onMessage;
  final VoidCallback? onBlock;
  final bool blocked;
  final bool preview;

  /// Crop editors inject the draft image into the same masks as saved profiles.
  final Widget? avatarPreview;
  final Widget? bannerPreview;
  final double minimumHeight;

  /// When supplied by a bounded mobile sheet, only the contents scroll; the
  /// gradient, rounded mask and outline remain fixed in place.
  final ScrollController? scrollController;
  final bool scrollable;
  final Widget? footer;
  final Future<Uint8List?> Function(bool banner)? loadImage;

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
    final card = Container(
      key: const Key('profile-card'),
      constraints: BoxConstraints(minHeight: minimumHeight),
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
      child: _ProfileScrollBody(
        controller: scrollController,
        enabled: scrollable || scrollController != null,
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
              avatarPreview: avatarPreview,
              bannerPreview: bannerPreview,
              loadImage: preview ? null : loadImage,
              viewImages: !preview,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                          '${profile.userId}${profile.pronouns?.trim().isNotEmpty == true ? '  •  ${profile.pronouns!.characters.take(16)}' : ''}',
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
                  if (profile.serverRoleNames.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final name in profile.serverRoleNames)
                          Chip(label: Text(name)),
                      ],
                    ),
                  ],
                  if (!preview) ActivityBlock(userId: profile.userId),
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
                            '${TimezoneCatalog.offsetLabel(timezone)}  •  ${TimezoneCatalog.localTimeLabel(timezone)}',
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
                                foregroundColor:
                                    deltiecordContrastingForeground(accent),
                              ),
                            ),
                          ),
                        if (onMessage != null && onBlock != null)
                          const SizedBox(width: 10),
                        if (onBlock != null)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onBlock,
                              icon: ThemeIcon(
                                blocked ? Icons.undo : Icons.block,
                              ),
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
                  if (!preview) LastFmRecentBar(userId: profile.userId),
                  ?footer,
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return preview
        ? card
        : ProfileWatch(
            backend: ActivityScope.of(context),
            id: profile.userId,
            expanded: true,
            child: card,
          );
  }
}

class _ProfileScrollBody extends StatelessWidget {
  const _ProfileScrollBody({
    required this.controller,
    required this.child,
    required this.enabled,
  });
  final ScrollController? controller;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => !enabled
      ? child
      : ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: controller,
            primary: false,
            child: child,
          ),
        );
}

class ProfileStatusBubble extends StatelessWidget {
  const ProfileStatusBubble({
    required this.status,
    required this.accent,
    super.key,
  });

  final String status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final fill = Color.alphaBlend(
      accent.withValues(alpha: .12),
      context.deltiecord.elevated,
    );
    return Tooltip(
      message: status,
      child: CustomPaint(
        painter: _ThoughtBubblePainter(fill, accent.withValues(alpha: .3)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            status.replaceAll(RegExp(r'\s+'), ' ').trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// Union the overlapping lobes before stroking, so the thought trail belongs
/// to the bubble instead of leaving detached circles or interior outline seams.
class _ThoughtBubblePainter extends CustomPainter {
  const _ThoughtBubblePainter(this.fill, this.outline);
  final Color fill;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    for (final circle in [
      Rect.fromLTWH(-8, size.height * .48, 18, 18),
      Rect.fromLTWH(-16, size.height * .48 + 10, 12, 12),
      Rect.fromLTWH(-21, size.height * .48 + 17, 8, 8),
    ]) {
      path = Path.combine(PathOperation.union, path, Path()..addOval(circle));
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ThoughtBubblePainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.outline != outline;
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.accent,
    required this.secondaryAccent,
    required this.onEdit,
    required this.onClose,
    this.avatarPreview,
    this.bannerPreview,
    this.loadImage,
    this.viewImages = true,
  });

  final UserProfileSummary profile;
  final Color accent;
  final Color secondaryAccent;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;
  final Widget? avatarPreview;
  final Widget? bannerPreview;
  final Future<Uint8List?> Function(bool banner)? loadImage;
  final bool viewImages;

  Widget _viewable(
    BuildContext context,
    Widget child,
    Uint8List? bytes,
    bool banner,
  ) {
    if (!viewImages || bytes == null) return child;
    return Semantics(
      button: true,
      label: banner ? 'View banner' : 'View avatar',
      child: GestureDetector(
        onTap: () => showProfileMedia(
          context,
          bytes,
          loadImage == null ? null : () => loadImage!(banner),
        ),
        child: MouseRegion(cursor: SystemMouseCursors.click, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.deltiecord;
    return LayoutBuilder(
      builder: (context, constraints) {
        // All profile surfaces, including the editor, share this geometry.
        final bannerHeight = constraints.maxWidth / profileBannerAspectRatio;
        final avatarSize = (constraints.maxWidth * .26).clamp(64.0, 124.0);
        final presenceSize = (avatarSize * .18).clamp(14.0, 20.0) * 1.1;
        final presenceInset =
            (avatarSize / 2 -
                    avatarSize * .3535533906 -
                    presenceBadgeSize(
                          presenceSize,
                          phone: showsMobilePresence(
                            context,
                            profile.userId,
                            profile.presence,
                          ),
                        ) /
                        2)
                .clamp(0.0, avatarSize)
                .toDouble();
        return SizedBox(
          height: bannerHeight + avatarSize / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: bannerHeight,
                child: _viewable(
                  context,
                  bannerPreview ??
                      (profile.bannerBytes == null
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
                            )),
                  profile.bannerBytes,
                  true,
                ),
              ),
              Positioned(
                left: 16,
                bottom: 0,
                child: _viewable(
                  context,
                  AvatarPresence(
                    presence: profile.presence,
                    userId: profile.userId,
                    badgeSize: presenceSize,
                    right: presenceInset,
                    bottom: presenceInset,
                    clearance:
                        showsMobilePresence(
                          context,
                          profile.userId,
                          profile.presence,
                        )
                        ? 2 + presenceBadgeSize(presenceSize) * .05
                        : 2,
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
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
                        // The existing banner/body gradient shows through;
                        // there is no separately painted avatar bezel.
                        color: Colors.transparent,
                      ),
                      child: ThemeAvatarClip(
                        clipBehavior: Clip.antiAlias,
                        child: _ProfileAvatarBackdrop(
                          child:
                              avatarPreview ??
                              (profile.avatarBytes == null
                                  ? Center(
                                      child: Text(
                                        profile
                                                .displayName
                                                .characters
                                                .firstOrNull
                                                ?.toUpperCase() ??
                                            '?',
                                        style: const TextStyle(
                                          fontSize: 42,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : hasAnimatedImageHeader(profile.avatarBytes!)
                                  ? LifecycleMemoryImage(
                                      bytes: profile.avatarBytes!,
                                      animated: true,
                                      decodeWidth: 512,
                                      autoplay: !MediaQuery.disableAnimationsOf(
                                        context,
                                      ),
                                      fit: BoxFit.cover,
                                    )
                                  : Image.memory(
                                      profile.avatarBytes!,
                                      fit: BoxFit.cover,
                                      cacheWidth: 256,
                                      cacheHeight: 256,
                                      gaplessPlayback: true,
                                      filterQuality: FilterQuality.high,
                                    )),
                        ),
                      ),
                    ),
                  ),
                  profile.avatarBytes,
                  false,
                ),
              ),
              Positioned(
                right: 20,
                left: 28 + avatarSize,
                bottom: 34,
                child: profile.presence == UserPresence.offline
                    ? const SizedBox.shrink()
                    : profile.statusMessage?.trim().isNotEmpty == true
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: ProfileStatusBubble(
                          status: profile.statusMessage!,
                          accent: accent,
                        ),
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
                              PresenceBadge(
                                presence: profile.presence,
                                phone: showsMobilePresence(
                                  context,
                                  profile.userId,
                                  profile.presence,
                                ),
                                size: presenceBadgeSize(
                                  9,
                                  phone: showsMobilePresence(
                                    context,
                                    profile.userId,
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

/// Continue the card's actual gradient behind transparent avatar pixels. The
/// shader uses the card's coordinates, not a new gradient fitted to the circle.
class _ProfileAvatarBackdrop extends SingleChildRenderObjectWidget {
  const _ProfileAvatarBackdrop({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ProfileAvatarBackdropBox();
}

class _ProfileAvatarBackdropBox extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    for (RenderObject? node = parent; node != null; node = node.parent) {
      if (node is! RenderDecoratedBox) continue;
      final decoration = node.decoration;
      if (decoration is! BoxDecoration || decoration.gradient == null) continue;
      final origin = globalToLocal(node.localToGlobal(Offset.zero));
      context.canvas.drawRect(
        offset & size,
        Paint()
          ..shader = decoration.gradient!.createShader(
            (origin & node.size).shift(offset),
          ),
      );
      break;
    }
    super.paint(context, offset);
  }
}

String _profilePresenceLabel(UserPresence presence) => switch (presence) {
  UserPresence.online => 'Online',
  UserPresence.away => 'Away',
  UserPresence.doNotDisturb => 'Do not disturb',
  UserPresence.offline => 'Offline',
};
