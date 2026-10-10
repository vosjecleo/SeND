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
      backend.rtcConnectivity.connectedPeers == 0) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No one is connected to you yet'),
        content: const Text(
          'You can wait in the voice channel alone, but audio, video and screen '
          'sharing need another connected participant. Wait for someone to join '
          'and for the connection icon to turn green, then share your screen.',
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
