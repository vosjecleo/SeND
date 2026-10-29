import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One pulse per threshold crossing. Falling below re-arms it; holding beyond
/// the threshold never repeats the tick or animation.
class ThresholdFeedbackIcon extends StatefulWidget {
  const ThresholdFeedbackIcon({
    required this.active,
    required this.icon,
    this.haptics = true,
    super.key,
  });
  final bool active;
  final IconData icon;
  final bool haptics;
  @override
  State<ThresholdFeedbackIcon> createState() => _ThresholdFeedbackIconState();
}

class _ThresholdFeedbackIconState extends State<ThresholdFeedbackIcon>
    with SingleTickerProviderStateMixin {
  bool _pulsed = false;
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _crossed();
    });
  }

  void _crossed() {
    if (_pulsed) return;
    _pulsed = true;
    if (widget.haptics &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      HapticFeedback.selectionClick();
    }
    if (!MediaQuery.disableAnimationsOf(context)) _pulse.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant ThresholdFeedbackIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _crossed();
    } else if (!widget.active && oldWidget.active) {
      _pulsed = false;
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, _) {
      final pulse = MediaQuery.disableAnimationsOf(context)
          ? 0.0
          : math.sin(math.pi * _pulse.value);
      return Transform.scale(
        scale: 1 + .15 * pulse,
        child: Icon(
          widget.icon,
          color: Color.lerp(
            Theme.of(context).colorScheme.onSurfaceVariant,
            Theme.of(context).colorScheme.primary,
            widget.active ? .6 + .4 * pulse : 0,
          ),
        ),
      );
    },
  );
}

/// Shared by regular messages and conversations opened through other paths.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    required this.messageId,
    required this.onReply,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final String messageId;
  final VoidCallback onReply;
  final Widget child;
  final bool enabled;
  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  bool _ready = false;
  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey('swipe-${widget.messageId}'),
    direction: widget.enabled
        ? DismissDirection.endToStart
        : DismissDirection.none,
    dismissThresholds: const {DismissDirection.endToStart: .15},
    onUpdate: (details) {
      if (_ready != details.reached) setState(() => _ready = details.reached);
    },
    confirmDismiss: (_) async {
      widget.onReply();
      return false;
    },
    background: Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: 24),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ThresholdFeedbackIcon(active: _ready, icon: Icons.reply),
    ),
    child: widget.child,
  );
}
