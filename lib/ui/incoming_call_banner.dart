import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';

/// A call invitation never takes over the current conversation or joins audio
/// without an explicit answer. Shared by the desktop and phone shells.
class IncomingCallBanner extends StatelessWidget {
  const IncomingCallBanner({required this.backend, super.key});
  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    final call = backend.incomingCall;
    if (call == null) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Card(
          margin: const EdgeInsets.all(12),
          elevation: 12,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.call),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${call.callerName} is calling…')),
                  IconButton(
                    tooltip: 'Decline call',
                    onPressed: backend.dismissIncomingCall,
                    icon: const Icon(Icons.call_end),
                  ),
                  FilledButton(
                    onPressed: () async {
                      backend.dismissIncomingCall();
                      try {
                        backend.selectSpace(null);
                        await backend.selectRoom(call.roomId);
                        await backend.joinVoiceRoom(call.roomId);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not answer the call: $error',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Answer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
