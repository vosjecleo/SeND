import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

class VoiceRoomView extends StatefulWidget {
  const VoiceRoomView({required this.backend, required this.room, super.key});

  final ChatBackend backend;
  final RoomSummary room;

  @override
  State<VoiceRoomView> createState() => _VoiceRoomViewState();
}

class _VoiceRoomViewState extends State<VoiceRoomView> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.backend.refreshAudioInputs());
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: const BoxDecoration(
          color: Color(0xff292a30),
          border: Border(bottom: BorderSide(color: Color(0xff35363d))),
        ),
        child: Row(
          children: [
            const Icon(Icons.volume_up_outlined, size: 20),
            const SizedBox(width: 9),
            Text(
              widget.room.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.headset_mic_outlined, size: 42),
                const SizedBox(height: 12),
                Text(
                  widget.room.voiceParticipants.isEmpty
                      ? 'Nobody is connected'
                      : '${widget.room.voiceParticipants.length} connected',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final participant in widget.room.voiceParticipants)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundImage: participant.avatarBytes == null
                          ? null
                          : MemoryImage(participant.avatarBytes!),
                      child: participant.avatarBytes == null
                          ? Text(participant.displayName.characters.first)
                          : null,
                    ),
                    title: Text(participant.displayName),
                    trailing: participant.speaking
                        ? const Icon(Icons.graphic_eq, color: Color(0xff76d49b))
                        : null,
                  ),
                if (widget.backend.voiceError case final error?) ...[
                  const SizedBox(height: 10),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xffff9b9b)),
                  ),
                ],
                const SizedBox(height: 18),
                if (widget.backend.audioInputs.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: widget.backend.selectedAudioInputId ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Microphone',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('System default'),
                      ),
                      for (final input in widget.backend.audioInputs)
                        DropdownMenuItem(
                          value: input.id,
                          child: Text(
                            input.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => widget.backend.selectAudioInput(
                      id?.isEmpty == true ? null : id,
                    ),
                  ),
                const SizedBox(height: 12),
                _VoiceControls(backend: widget.backend, room: widget.room),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _VoiceControls extends StatelessWidget {
  const _VoiceControls({required this.backend, required this.room});

  final ChatBackend backend;
  final RoomSummary room;

  @override
  Widget build(BuildContext context) {
    final connectedHere = backend.activeVoiceRoomId == room.id;
    final busy =
        backend.voiceConnectionStatus == VoiceConnectionStatus.connecting ||
        backend.voiceConnectionStatus == VoiceConnectionStatus.disconnecting;
    if (!connectedHere) {
      return FilledButton.icon(
        onPressed: busy ? null : () => backend.joinVoiceRoom(room.id),
        icon: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.headset),
        label: const Text('Join voice'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => backend.setVoiceMuted(!backend.voiceMuted),
            icon: Icon(backend.voiceMuted ? Icons.mic_off : Icons.mic),
            label: Text(backend.voiceMuted ? 'Unmute' : 'Mute'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : backend.leaveVoiceRoom,
            icon: const Icon(Icons.call_end),
            label: const Text('Disconnect'),
          ),
        ),
      ],
    );
  }
}
