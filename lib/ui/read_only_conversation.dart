import 'package:flutter/material.dart';

class ReadOnlyConversationNotice extends StatelessWidget {
  const ReadOnlyConversationNotice({super.key});

  @override
  Widget build(BuildContext context) => const SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text('You cannot send messages in this channel.'),
    ),
  );
}
