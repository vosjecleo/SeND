import 'package:flutter/material.dart';

/// Keeps the conversation mounted when a call starts or ends. Stream/video
/// fullscreen remains a separate route, so neither draft nor scroll is lost.
class CallAndChatLayout extends StatelessWidget {
  const CallAndChatLayout({required this.chat, this.call, super.key});
  final Widget chat;
  final Widget? call;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final showCall = call != null && constraints.maxHeight >= 360;
      final top = MediaQuery.paddingOf(context).top;
      return Column(
        children: [
          if (showCall)
            SizedBox(
              height: (constraints.maxHeight * .40)
                  .clamp(
                    0,
                    constraints.maxWidth < 700
                        ? ((constraints.maxWidth - 24) / 2 * 9 / 16 + 76 + top)
                              .clamp(0.0, 340.0 + top)
                        : 340 + top,
                  )
                  .toDouble(),
              child: SafeArea(bottom: false, child: call!),
            ),
          Expanded(
            key: const ValueKey('call-chat-conversation'),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: showCall,
              child: chat,
            ),
          ),
        ],
      );
    },
  );
}
