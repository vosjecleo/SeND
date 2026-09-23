import 'package:flutter/material.dart';

/// Fade the old page out before showing the new one. A simultaneous crossfade
/// or short slide of transparent pages superimposes their text mid-transition.
class SettingsPageTransition extends StatelessWidget {
  const SettingsPageTransition({
    required this.child,
    required this.reduceMotion,
    super.key,
  });

  final Widget child;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [
            for (final old in previous)
              ExcludeSemantics(child: IgnorePointer(child: old)),
            ?current,
          ],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation.drive(CurveTween(curve: const Interval(0.5, 1))),
          child: child,
        ),
        child: child,
      ),
    ),
  );
}
