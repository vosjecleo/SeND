import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Claim the hold after a second, but do not begin dragging until movement.
class HoldMoveDraggable<T extends Object> extends Draggable<T> {
  const HoldMoveDraggable({
    required super.data,
    required super.feedback,
    required super.child,
    super.childWhenDragging,
    super.onDragStarted,
    super.onDragEnd,
    super.key,
  }) : super(
         maxSimultaneousDrags: 1,
         dragAnchorStrategy: pointerDragAnchorStrategy,
       );
  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _HoldMoveRecognizer(debugOwner: this)..onStart = onStart;
}

class _HoldMoveRecognizer extends MultiDragGestureRecognizer {
  _HoldMoveRecognizer({super.debugOwner})
    : super(allowedButtonsFilter: (buttons) => buttons == kPrimaryButton);
  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _HoldMovePointer(event.position, event.kind, gestureSettings);
  @override
  String get debugDescription => 'hold then move';
}

class _HoldMovePointer extends MultiDragPointerState {
  _HoldMovePointer(super.initialPosition, super.kind, super.gestureSettings) {
    _claim = Timer(const Duration(milliseconds: 500), () {
      if (_starter == null) resolve(GestureDisposition.accepted);
    });
    _timer = Timer(const Duration(seconds: 1), () {
      _ready = true;
      if (_starter == null) resolve(GestureDisposition.accepted);
      _maybeStart();
    });
  }
  Timer? _timer, _claim;
  bool _ready = false;
  GestureMultiDragStartCallback? _starter;
  void _maybeStart() {
    if (_ready &&
        _starter != null &&
        (pendingDelta?.distance ?? 0) > computeHitSlop(kind, gestureSettings)) {
      final start = _starter!;
      _starter = null;
      start(initialPosition);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    _starter = starter;
    _maybeStart();
  }

  @override
  void checkForResolutionAfterMove() {
    if (!_ready &&
        (pendingDelta?.distance ?? 0) > computeHitSlop(kind, gestureSettings)) {
      _timer?.cancel();
      _claim?.cancel();
      resolve(GestureDisposition.rejected);
      return;
    }
    _maybeStart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _claim?.cancel();
    super.dispose();
  }
}
