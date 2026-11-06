import 'dart:math';
import 'package:flutter/widgets.dart';

double timelineMediaWidthLimit(Size screen, {required bool mobile}) => mobile
    ? min(420, max(120, screen.width - 76))
    : min(420, screen.width * .5);

Size fitTimelineMediaFrame({
  required double maxWidth,
  required double maxHeight,
  int? width,
  int? height,
  double fallbackAspectRatio = 3 / 4,
}) {
  final ratio = width != null && height != null && width > 0 && height > 0
      ? width / height
      : fallbackAspectRatio;
  final aspect = ratio.isFinite
      ? ratio.clamp(.25, 4).toDouble()
      : fallbackAspectRatio;
  return maxWidth / maxHeight > aspect
      ? Size(maxHeight * aspect, maxHeight)
      : Size(maxWidth, maxWidth / aspect);
}

/// Pending and delivered images reserve the same timeline rectangle.
Size timelineImageFrameSize({
  required Size screen,
  required bool mobile,
  double availableWidth = double.infinity,
  int? width,
  int? height,
  bool spoiler = false,
}) => fitTimelineMediaFrame(
  maxWidth: min(
    availableWidth,
    timelineMediaWidthLimit(screen, mobile: mobile),
  ),
  maxHeight: mobile
      ? min(520, max(180, screen.height * (spoiler ? .52 : .48)))
      : min(520, screen.height * .5),
  width: width,
  height: height,
);
