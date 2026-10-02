import 'package:flutter/material.dart';

/// Keeps the conversation mounted when a call starts or ends. Stream/video
/// fullscreen remains a separate route, so neither draft nor scroll is lost.
class CallAndChatLayout extends StatelessWidget {
  const CallAndChatLayout({required this.chat, this.call, super.key});
  final Widget chat;
  final Widget? call;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        if (call != null && constraints.maxHeight >= 360)
          SizedBox(
            height: (constraints.maxHeight * .40).clamp(0, 340).toDouble(),
            child: call,
          ),
        Expanded(key: const ValueKey('call-chat-conversation'), child: chat),
      ],
    ),
  );
}
