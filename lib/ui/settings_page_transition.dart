import 'package:flutter/material.dart';

/// Paint only the incoming page. Keeping outgoing transparent pages around
/// superimposes their text when navigation is interrupted or reversed.
class SettingsPageTransition extends StatelessWidget {
  const SettingsPageTransition({
    required this.child,
    required this.reduceMotion,
    this.backwards = false,
    super.key,
  });

  final Widget child;
  final bool reduceMotion;
  final bool backwards;

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
            // Only the current page may paint. Interrupted transitions can
            // leave several outgoing pages alive with nonzero opacity.
            ?current,
          ],
        ),
        transitionBuilder: (child, animation) => SlideTransition(
          position: animation.drive(
            Tween(
              begin: Offset(backwards ? -0.12 : 0.12, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: child,
      ),
    ),
  );
}
