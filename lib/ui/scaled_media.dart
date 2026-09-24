import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Keep safe areas in the same coordinate system as the scaled app. Insets
/// are merged, never summed: platforms already reporting them must not shift.
MediaQueryData scaledAppMedia(
  MediaQueryData media,
  double scale,
  EdgeInsets browserInsets,
) {
  final safe = EdgeInsets.fromLTRB(
    math.max(media.viewPadding.left, browserInsets.left),
    math.max(media.viewPadding.top, browserInsets.top),
    math.max(media.viewPadding.right, browserInsets.right),
    math.max(media.viewPadding.bottom, browserInsets.bottom),
  );
  final padding = EdgeInsets.fromLTRB(
    math.max(0, safe.left - media.viewInsets.left),
    math.max(0, safe.top - media.viewInsets.top),
    math.max(0, safe.right - media.viewInsets.right),
    math.max(0, safe.bottom - media.viewInsets.bottom),
  );
  return media.copyWith(
    size: media.size / scale,
    padding: padding / scale,
    viewPadding: safe / scale,
    viewInsets: media.viewInsets / scale,
    systemGestureInsets: media.systemGestureInsets / scale,
  );
}
