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
  late int _profileRevision = widget.backend.profileRevision;

  Future<UserProfileSummary> _load() =>
      widget.backend.getUserProfile(widget.member.userId);

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_backendChanged);
  }

  void _backendChanged() {
    final revision = widget.backend.profileRevision;
    if (!mounted || revision == _profileRevision) return;
    _profileRevision = revision;
    setState(() => _profile = _load());
  }

  @override
  void didUpdateWidget(covariant _RecipientProfilePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.userId != widget.member.userId) {
      _profile = _load();
    }
    if (oldWidget.backend != widget.backend) {
      oldWidget.backend.removeListener(_backendChanged);
      widget.backend.addListener(_backendChanged);
      _profileRevision = widget.backend.profileRevision;
      _profile = _load();
    }
  }

  @override
  void dispose() {
    widget.backend.removeListener(_backendChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.deltiecord.panel,
    child: Padding(
      key: const Key('recipient-profile-panel'),
      padding: const EdgeInsets.fromLTRB(10, 8, 12, _bottomPanelVerticalInset),
      child: FutureBuilder<UserProfileSummary>(
        future: _profile,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading profile…'),
                ],
              ),
            );
          }
          return _RecipientProfileContents(
            backend: widget.backend,
            member: widget.member,
            profile: profile,
            loading: false,
          );
        },
      ),
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
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                key: const Key('recipient-profile-gradient'),
                child: DeltiecordProfileCard(
                  profile: profile,
                  minimumHeight: constraints.maxHeight,
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: _bottomPanelHeightFor(context) - _bottomPanelVerticalInset,
          child: ColoredBox(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                key: const Key('view-full-profile-island'),
                width: double.infinity,
                child: ThemeSurface.wrap(
                  context,
                  kind: 'button',
                  color: palette.island,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(context)
                                  .extension<ThemeChrome>()
                                  ?.surfaces
                                  .containsKey('button') ==
                              true
                          ? Colors.transparent
                          : palette.island.withValues(alpha: .9),
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: DeltiecordCorners.borderRadius,
                      ),
                    ),
                    onPressed: () =>
                        showFullMemberProfile(context, backend, member),
                    child: const Text('View full profile'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
