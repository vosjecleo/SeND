import 'package:flutter/material.dart';
import 'deltiecord_theme.dart';

/// A chat's pin and activity time share one compact trailing line.
class ChatActivityStamp extends StatelessWidget {
  const ChatActivityStamp({required this.age, required this.pinned, super.key});
  final String age;
  final bool pinned;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (pinned) ...[
        Tooltip(
          message: 'Pinned chat',
          child: Icon(
            Icons.push_pin,
            size: 11,
            color: context.deltiecord.muted,
          ),
        ),
        if (age.isNotEmpty) const SizedBox(width: 4),
      ],
      if (age.isNotEmpty)
        Text(
          age,
          style: TextStyle(
            color: context.deltiecord.muted,
            fontSize: DeltiecordTypeScale.small,
            height: 1.05,
          ),
        ),
    ],
  );
}
