import 'package:flutter/material.dart';

/// The marker is painted over the row, never added to ListTile.trailing.
/// Joined and unjoined channels keep identical row constraints and spacing.
class ChannelJoinIndicator extends StatelessWidget {
  const ChannelJoinIndicator({
    required this.joined,
    required this.child,
    super.key,
  });
  final bool joined;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      if (!joined)
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Center(
              child: Tooltip(
                message: 'Not joined. Open this channel to join.',
                child: Semantics(
                  label: 'Channel not joined',
                  child: const Icon(
                    Icons.error_outline,
                    key: ValueKey('unjoined-channel-indicator'),
                    color: Colors.redAccent,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
