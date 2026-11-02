import 'package:flutter/material.dart';
import 'deltiecord_theme.dart';

/// Draft reply/edit focus and neutral navigation pulses override mentions.
BoxDecoration messageHighlightDecoration(
  BuildContext context, {
  required bool mentioned,
  required bool replying,
  required bool flashing,
  Color idleColour = Colors.transparent,
}) {
  if (flashing) return BoxDecoration(color: context.deltiecord.hover);
  const focus = Color(0xff408cff);
  final colour = replying
      ? focus
      : mentioned
      ? Theme.of(context).colorScheme.primary
      : null;
  return BoxDecoration(
    color: colour?.withValues(alpha: replying ? .17 : .11) ?? idleColour,
    border: colour == null
        ? null
        : Border(left: BorderSide(color: colour, width: 3)),
  );
}
