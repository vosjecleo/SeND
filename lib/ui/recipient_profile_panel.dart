part of 'chat_shell.dart';

/// Persistent, compact profile summary shown beside direct conversations.
///
/// This deliberately consumes only [ChatBackend] models so Matrix SDK objects
/// remain behind the application boundary.
class _RecipientProfilePanel extends StatefulWidget {
  const _RecipientProfilePanel({required this.backend, required this.member});

  final ChatBackend backend;
  final RoomMemberSummary member;

  @override
  State<_RecipientProfilePanel> createState() => _RecipientProfilePanelState();
}

class _RecipientProfilePanelState extends State<_RecipientProfilePanel> {
  late Future<UserProfileSummary> _profile = _load();

  Future<UserProfileSummary> _load() =>
      widget.backend.getUserProfile(widget.member.userId);

  @override
  void didUpdateWidget(covariant _RecipientProfilePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.userId != widget.member.userId) {
      _profile = _load();
    }
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const Key('recipient-profile-panel'),
    decoration: BoxDecoration(
      color: context.deltiecord.panel,
      border: Border(left: BorderSide(color: context.deltiecord.divider)),
    ),
    child: FutureBuilder<UserProfileSummary>(
      future: _profile,
      builder: (context, snapshot) {
        final profile =
            snapshot.data ??
            UserProfileSummary(
              userId: widget.member.userId,
              displayName: widget.member.displayName,
              avatarBytes: widget.member.avatarBytes,
              presence: widget.member.presence,
            );
        return _RecipientProfileContents(
          backend: widget.backend,
          member: widget.member,
          profile: profile,
          loading: snapshot.connectionState == ConnectionState.waiting,
        );
      },
    ),
  );
}

class _RecipientProfileContents extends StatelessWidget {
  const _RecipientProfileContents({
    required this.backend,
    required this.member,
    required this.profile,
    required this.loading,
  });

  final ChatBackend backend;
  final RoomMemberSummary member;
  final UserProfileSummary profile;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.deltiecord;
    final accent = Color(
      profile.profileColor ?? Theme.of(context).colorScheme.primary.toARGB32(),
    );
    final secondary = Color(
      profile.profileColorSecondary ??
          Color.lerp(accent, palette.rail, 0.58)!.toARGB32(),
    );
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 204,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        bottom: 58,
                        child: profile.bannerBytes == null
                            ? DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [accent, secondary],
                                  ),
                                ),
                              )
                            : Image.memory(
                                profile.bannerBytes!,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                              ),
                      ),
                      Positioned(
                        left: 20,
                        bottom: 18,
                        child: _RecipientAvatar(
                          profile: profile,
                          fallback: member,
                          panelColor: palette.panel,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: DeltiecordTypeScale.bigUi,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (profile.statusMessage?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 14,
                              color: accent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                profile.statusMessage!,
                                style: TextStyle(color: palette.muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      SelectableText(
                        profile.userId,
                        style: TextStyle(color: palette.muted),
                      ),
                      if (profile.pronouns?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 7),
                        Text(
                          profile.pronouns!,
                          style: TextStyle(color: palette.muted),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (profile.bio?.trim().isNotEmpty == true)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.surface,
                            border: Border.all(color: palette.divider),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ABOUT ME',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: DeltiecordTypeScale.normal,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(profile.bio!),
                              ],
                            ),
                          ),
                        ),
                      if (loading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => showMemberProfile(context, backend, member),
              child: const Text('View full profile'),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecipientAvatar extends StatelessWidget {
  const _RecipientAvatar({
    required this.profile,
    required this.fallback,
    required this.panelColor,
  });

  final UserProfileSummary profile;
  final RoomMemberSummary fallback;
  final Color panelColor;

  @override
  Widget build(BuildContext context) {
    final bytes = profile.avatarBytes ?? fallback.avatarBytes;
    final presence = profile.presence;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 88,
          height: 88,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: panelColor, shape: BoxShape.circle),
          child: CircleAvatar(
            backgroundImage: bytes == null ? null : MemoryImage(bytes),
            child: bytes == null
                ? Text(
                    profile.displayName.trim().isEmpty
                        ? '?'
                        : profile.displayName.characters.first,
                    style: const TextStyle(fontSize: 30),
                  )
                : null,
          ),
        ),
        Positioned(
          right: 2,
          bottom: 3,
          child: Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              color: switch (presence) {
                UserPresence.online => const Color(0xff23d18b),
                UserPresence.away => const Color(0xffffc857),
                UserPresence.offline => const Color(0xff686a73),
              },
              shape: BoxShape.circle,
              border: Border.all(color: panelColor, width: 4),
            ),
          ),
        ),
      ],
    );
  }
}
