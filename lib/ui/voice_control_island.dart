import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/rtc_connectivity.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';

Future<void> toggleVoiceScreenSharing(
  BuildContext context,
  ChatBackend backend,
) async {
  if (!backend.voiceScreenSharing &&
      backend.voiceConnectionStatus != VoiceConnectionStatus.connected) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to the call first'),
        content: const Text(
          'Wait for the call to connect, then share your screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  await backend.setVoiceScreenSharing(!backend.voiceScreenSharing);
}

class RtcConnectivityIcon extends StatelessWidget {
  const RtcConnectivityIcon({required this.backend, super.key});
  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    if (backend.voiceConnectionStatus == VoiceConnectionStatus.disconnected) {
      return const SizedBox.shrink();
    }
    final status = backend.rtcConnectivity;
    final (icon, color) = switch (status.state) {
      RtcConnectivityState.unavailable => (Icons.error, Colors.redAccent),
      RtcConnectivityState.waiting => (Icons.help, Colors.orange),
      RtcConnectivityState.connected => (
        Icons.signal_cellular_alt,
        Colors.green,
      ),
    };
    return Tooltip(
      message: status.description,
      child: IconButton(
        tooltip: null,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Voice connection'),
            content: ListenableBuilder(
              listenable: backend,
              builder: (context, _) =>
                  Text(backend.rtcConnectivity.description),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        icon: Icon(icon, color: color, semanticLabel: status.description),
      ),
    );
  }
}

class VoiceControlIsland extends StatelessWidget {
  const VoiceControlIsland({required this.backend, super.key});
  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: backend,
    builder: (context, _) => Material(
      elevation: 6,
      color: context.deltiecord.elevated,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            RtcConnectivityIcon(backend: backend),
            IconButton(
              tooltip: backend.voiceMuted ? 'Unmute' : 'Mute',
              onPressed: () => backend.setVoiceMuted(!backend.voiceMuted),
              icon: Icon(backend.voiceMuted ? Icons.mic_off : Icons.mic),
            ),
            IconButton(
              tooltip: backend.voiceDeafened ? 'Undeafen' : 'Deafen',
              onPressed: () => backend.setVoiceDeafened(!backend.voiceDeafened),
              icon: Icon(
                backend.voiceDeafened ? Icons.headset_off : Icons.headset,
              ),
            ),
            IconButton(
              tooltip: backend.voiceCameraEnabled ? 'Camera off' : 'Camera on',
              onPressed: () =>
                  backend.setVoiceCameraEnabled(!backend.voiceCameraEnabled),
              icon: Icon(
                backend.voiceCameraEnabled
                    ? Icons.videocam
                    : Icons.videocam_off,
              ),
            ),
            IconButton(
              tooltip: 'Disconnect',
              onPressed: backend.leaveVoiceRoom,
              icon: Icon(
                Icons.call_end,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The same primary controls in a full voice room and an embedded DM call.
class VoiceCallControls extends StatelessWidget {
  const VoiceCallControls({
    required this.backend,
    this.options,
    this.showConnectivity = false,
    super.key,
  });
  final ChatBackend backend;
  final Widget? options;
  final bool showConnectivity;
  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('voice-call-controls'),
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      if (showConnectivity) RtcConnectivityIcon(backend: backend),
      IconButton(
        tooltip: backend.voiceMuted ? 'Unmute' : 'Mute',
        onPressed: () => backend.setVoiceMuted(!backend.voiceMuted),
        icon: Icon(backend.voiceMuted ? Icons.mic_off : Icons.mic),
      ),
      IconButton(
        tooltip: backend.voiceDeafened ? 'Undeafen' : 'Deafen',
        onPressed: () => backend.setVoiceDeafened(!backend.voiceDeafened),
        icon: Icon(backend.voiceDeafened ? Icons.headset_off : Icons.headset),
      ),
      IconButton(
        tooltip: backend.voiceCameraEnabled ? 'Camera off' : 'Camera on',
        onPressed: () =>
            backend.setVoiceCameraEnabled(!backend.voiceCameraEnabled),
        icon: Icon(
          backend.voiceCameraEnabled ? Icons.videocam : Icons.videocam_off,
        ),
      ),
      IconButton(
        tooltip: 'Disconnect',
        onPressed: backend.leaveVoiceRoom,
        icon: Icon(Icons.call_end, color: Theme.of(context).colorScheme.error),
      ),
      ?options,
    ],
  );
}

/// Embedded calls fit the available stage instead of scrolling oversized tiles.
class CompactVoiceGrid extends StatelessWidget {
  const CompactVoiceGrid({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = (bounds.maxWidth >= 720 ? 3 : 2).clamp(
        1,
        itemCount > 0 ? itemCount : 1,
      );
      final rows = itemCount == 0 ? 1 : (itemCount / columns).ceil();
      final height = ((bounds.maxHeight - 16 - (rows - 1) * 8) / rows).clamp(
        60.0,
        double.infinity,
      );
      return GridView.builder(
        key: const ValueKey('compact-voice-grid'),
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: height,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: itemBuilder(context, index),
          ),
        ),
      );
    },
  );
}
