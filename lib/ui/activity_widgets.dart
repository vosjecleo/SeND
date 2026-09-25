import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../models/user_activity.dart';
import 'deltiecord_theme.dart';

class ActivityScope extends InheritedWidget {
  const ActivityScope({required this.backend, required super.child, super.key});
  final ChatBackend backend;
  static ChatBackend? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActivityScope>()?.backend;
  @override
  bool updateShouldNotify(ActivityScope oldWidget) =>
      oldWidget.backend != backend;
}

IconData activityIcon(ActivityKind kind) => switch (kind) {
  ActivityKind.game => Icons.sports_esports_outlined,
  ActivityKind.music => Icons.music_note,
  ActivityKind.application => Icons.apps,
};

class ActivityStatus extends StatelessWidget {
  const ActivityStatus({
    required this.backend,
    required this.userId,
    required this.presence,
    this.status,
    super.key,
  });
  final ChatBackend backend;
  final String? userId, status;
  final UserPresence presence;
  @override
  Widget build(BuildContext context) {
    if (presence == UserPresence.offline) return const SizedBox.shrink();
    final activity = userId == null ? null : backend.activityFor(userId!);
    final text = activity?.label ?? status?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final color = context.deltiecord.muted;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          if (activity != null) ...[
            Icon(activityIcon(activity.kind), size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityBlock extends StatelessWidget {
  const ActivityBlock({required this.userId, this.compact = false, super.key});
  final String? userId;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final backend = ActivityScope.of(context);
    if (backend == null || userId == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        final activity = backend.activityFor(userId!);
        if (activity == null) return const SizedBox.shrink();
        return Container(
          margin: EdgeInsets.symmetric(vertical: compact ? 0 : 10),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 18 : 12,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: context.deltiecord.elevated.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(compact ? 0 : 8),
          ),
          child: Row(
            children: [
              if (activity.icon != null)
                _ActivityArtwork(
                  backend: backend,
                  activity: activity,
                  size: compact
                      ? 32
                      : activity.kind == ActivityKind.music
                      ? 64
                      : 40,
                )
              else
                Icon(activityIcon(activity.kind), size: compact ? 18 : 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (activity.kind) {
                        ActivityKind.game => 'Currently playing:',
                        ActivityKind.music => 'Currently listening to:',
                        ActivityKind.application => 'Currently using:',
                      },
                      style: TextStyle(
                        fontSize: 12,
                        color: context.deltiecord.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (activity.details.isNotEmpty)
                      Text(
                        activity.details,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (activity.playback != null)
                      ActivityProgress(activity: activity),
                    if (activity.lastFmUrl != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                        ),
                        onPressed: () => launchUrl(
                          activity.lastFmUrl!,
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text(
                          'Powered by Last.fm / AudioScrobbler',
                          style: TextStyle(fontSize: 11),
                        ),
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

String activityClock(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Separate footer: a completed scrobble must never masquerade as live music
/// or replace a game/activity above. The backend enforces presence and expiry.
class LastFmRecentBar extends StatelessWidget {
  const LastFmRecentBar({required this.userId, super.key});
  final String userId;
  @override
  Widget build(BuildContext context) {
    final backend = ActivityScope.of(context);
    if (backend == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        final track = backend.lastFmRecentFor(userId);
        if (track == null) return const SizedBox.shrink();
        final palette = context.deltiecord;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Material(
            color: palette.elevated.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () =>
                  launchUrl(track.url, mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Tooltip(
                  message: '${track.name}\n${track.artist}\n${track.album}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last.fm · Last listened to',
                        style: TextStyle(fontSize: 11, color: palette.muted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          track.artist,
                          track.album,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.muted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Powered by AudioScrobbler',
                        style: TextStyle(fontSize: 10, color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ActivityProgress extends StatefulWidget {
  const ActivityProgress({required this.activity, super.key});
  final UserActivity activity;
  @override
  State<ActivityProgress> createState() => _ActivityProgressState();
}

class _ActivityProgressState extends State<ActivityProgress>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ActivityProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_visible ||
        !TickerMode.valuesOf(context).enabled ||
        widget.activity.playback?.playing != true ||
        widget.activity.expired) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (widget.activity.expired ||
          widget.activity.playback!.positionAt(DateTime.now()) >=
              widget.activity.playback!.durationMs) {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.activity.playback;
    if (playback == null || widget.activity.expired) {
      return const SizedBox.shrink();
    }
    final position = playback.positionAt(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: position / playback.durationMs,
            minHeight: 3,
            semanticsLabel:
                '${playback.playing ? 'Song progress' : 'Song paused'}: ${activityClock(position)} of ${activityClock(playback.durationMs)}',
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                activityClock(position),
                style: TextStyle(fontSize: 11, color: context.deltiecord.muted),
              ),
              Text(
                activityClock(playback.durationMs),
                style: TextStyle(fontSize: 11, color: context.deltiecord.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityArtwork extends StatefulWidget {
  const _ActivityArtwork({
    required this.backend,
    required this.activity,
    required this.size,
  });
  final ChatBackend backend;
  final UserActivity activity;
  final double size;
  @override
  State<_ActivityArtwork> createState() => _ActivityArtworkState();
}

class _ActivityArtworkState extends State<_ActivityArtwork> {
  late var _image = widget.backend.loadActivityIcon(widget.activity.icon!);
  @override
  void didUpdateWidget(covariant _ActivityArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity.icon != widget.activity.icon ||
        oldWidget.backend != widget.backend) {
      _image = widget.backend.loadActivityIcon(widget.activity.icon!);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _image,
    builder: (context, snapshot) => SizedBox.square(
      dimension: widget.size,
      child: snapshot.data == null
          ? Icon(activityIcon(widget.activity.kind))
          : ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                snapshot.data!,
                width: widget.size,
                height: widget.size,
                fit: widget.activity.kind == ActivityKind.music
                    ? BoxFit.cover
                    : BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Icon(activityIcon(widget.activity.kind)),
              ),
            ),
    ),
  );
}
