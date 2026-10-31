import 'package:flutter/material.dart';

import 'deltiecord_theme.dart';

const double typingIndicatorHeight = 16;

double typingIndicatorHeightFor(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(DeltiecordTypeScale.small) * 1.2 +
            1)
        .clamp(typingIndicatorHeight, double.infinity)
        .ceilToDouble();

/// A translucent timeline overlay for live typing activity.
///
/// Callers place this over the bottom of the timeline rather than allocating
/// a separate row. Messages therefore keep their natural proximity to the
/// composer and remain visible through the fade when typing starts.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    required this.names,
    this.textInset = 60,
    this.avatarInset = 10,
    super.key,
  });

  final List<String> names;
  final double textInset, avatarInset;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.names.isEmpty != widget.names.isEmpty) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.names.isEmpty) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.names.isNotEmpty;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    } else if (!reducedMotion && visible && !_controller.isAnimating) {
      _controller.repeat();
    }
    return Semantics(
      label: visible ? typingLabel(widget.names) : null,
      child: IgnorePointer(
        child: SizedBox(
          key: const Key('typing-indicator'),
          height: typingIndicatorHeightFor(context),
          child: DecoratedBox(
            key: const Key('typing-indicator-gradient'),
            decoration: BoxDecoration(
              color: visible ? context.deltiecord.background : null,
              gradient: visible
                  ? null
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.62, 0.92],
                      colors: [
                        context.deltiecord.background.withValues(alpha: 0),
                        context.deltiecord.background.withValues(alpha: 0.72),
                        context.deltiecord.background,
                      ],
                    ),
            ),
            child: AnimatedOpacity(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              opacity: visible ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 1, 8, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: widget.textInset,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: widget.avatarInset,
                          right: (widget.textInset - widget.avatarInset - 40)
                              .clamp(0, double.infinity),
                        ),
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (var index = 0; index < 3; index++) ...[
                                Opacity(
                                  opacity: _dotOpacity(
                                    _controller.value,
                                    index,
                                  ),
                                  child: SizedBox.square(
                                    key: ValueKey('typing-dot-$index'),
                                    dimension: MediaQuery.textScalerOf(
                                      context,
                                    ).scale(3).clamp(3, 5),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: context.deltiecord.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        key: const ValueKey('typing-indicator-label'),
                        visible ? typingLabel(widget.names) : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DeltiecordTypeScale.small,
                          height: 1.2,
                          color: context.deltiecord.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _dotOpacity(double progress, int index) {
    final shifted = (progress - index * 0.18) % 1.0;
    if (shifted < 0.22) return 0.25 + (shifted / 0.22) * 0.75;
    if (shifted < 0.44) return 1 - ((shifted - 0.22) / 0.22) * 0.75;
    return 0.25;
  }
}

String typingLabel(List<String> names) => switch (names.length) {
  0 => '',
  1 => '${names.first} is typing',
  2 => '${names.first} and ${names[1]} are typing',
  3 => '${names.first}, ${names[1]} and ${names[2]} are typing',
  _ => 'Several people are typing',
};
