import 'package:flutter/material.dart';

/// Explicit navigation owns the viewport until the new list has laid out.
/// Finish at the true extent, not at an offset captured before hydration.
Future<void> scrollToTimelinePresent({
  required ScrollController controller,
  required bool Function() isCurrent,
  bool reducedMotion = false,
}) async {
  if (!isCurrent()) return;
  WidgetsBinding.instance.scheduleFrame();
  await WidgetsBinding.instance.endOfFrame;
  if (!isCurrent() || !controller.hasClients) return;
  await controller.animateTo(
    controller.position.minScrollExtent,
    duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
    curve: Curves.easeOut,
  );
  for (var frame = 0; frame < 3; frame++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    if (!isCurrent() || !controller.hasClients) return;
    controller.jumpTo(controller.position.minScrollExtent);
  }
}

class SegmentTimelineAnchor {
  const SegmentTimelineAnchor(this.segmentId, this.position);
  final String? segmentId;
  final (String, double) position;
}

SegmentTimelineAnchor? captureSegmentTimelineAnchor(
  GlobalKey viewport,
  Map<String, GlobalKey> rows,
  String? segmentId,
) {
  final position = captureTimelineAnchor(viewport, rows);
  return position == null ? null : SegmentTimelineAnchor(segmentId, position);
}

void restoreSegmentTimelineAnchor(
  ScrollController controller,
  Map<String, GlobalKey> rows,
  SegmentTimelineAnchor? anchor,
  String? segmentId,
) {
  if (anchor == null || anchor.segmentId != segmentId) return;
  restoreTimelineAnchor(controller, rows, anchor.position);
}

/// Jump within an already loaded reversed timeline without refetching the room.
/// Lazy rows are located with bounded offset bisection, then aligned precisely.
Future<bool> scrollToTimelineRow({
  required ScrollController controller,
  required Map<String, GlobalKey> rowKeys,
  required List<String> ids,
  required String id,
  required bool Function() isCurrent,
  bool reducedMotion = false,
  int attempts = 16,
}) async {
  final index = ids.indexOf(id);
  if (index < 0) return false;
  final positions = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  double low = 0,
      high = controller.hasClients ? controller.position.maxScrollExtent : 0;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (!isCurrent()) return false;
    final target = rowKeys[id]?.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        alignment: .5,
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 160),
      );
      return isCurrent();
    }
    if (controller.hasClients) {
      final visible = [
        for (final row in rowKeys.entries)
          if (row.value.currentContext != null &&
              positions.containsKey(row.key))
            positions[row.key]!,
      ];
      if (visible.isNotEmpty) {
        visible.sort();
        if (index < visible.first) {
          high = controller.offset;
        } else if (index > visible.last) {
          low = controller.offset;
        }
      }
      if (high <= low) {
        low = 0;
        high = controller.position.maxScrollExtent;
      }
      final offset = attempt == 0
          ? index / (ids.length > 1 ? ids.length - 1 : 1) * high
          : (low + high) / 2;
      controller.jumpTo(offset.clamp(0, controller.position.maxScrollExtent));
    }
    await WidgetsBinding.instance.endOfFrame;
  }
  return false;
}

/// Geometry shared by room and thread timelines. Capture the row nearest the
/// leading viewport edge, including tall media, before metadata/history changes.
(String, double)? captureTimelineAnchor(
  GlobalKey viewportKey,
  Map<String, GlobalKey> rowKeys,
) {
  final viewport = viewportKey.currentContext?.findRenderObject();
  if (viewport is! RenderBox || !viewport.attached) return null;
  final top = viewport.localToGlobal(Offset.zero).dy;
  final bottom = top + viewport.size.height;
  (String, double)? closest;
  var distance = double.infinity;
  for (final entry in rowKeys.entries) {
    final row = entry.value.currentContext?.findRenderObject();
    if (row is! RenderBox || !row.attached) continue;
    final y = row.localToGlobal(Offset.zero).dy;
    if (y + row.size.height < top || y > bottom) continue;
    final candidate = (y - top).abs();
    if (candidate < distance) {
      distance = candidate;
      closest = (entry.key, y);
    }
  }
  return closest;
}

void restoreTimelineAnchor(
  ScrollController controller,
  Map<String, GlobalKey> rowKeys,
  (String, double)? anchor,
) {
  if (anchor == null || !controller.hasClients) return;
  final row = rowKeys[anchor.$1]?.currentContext?.findRenderObject();
  if (row is! RenderBox || !row.attached) return;
  final y = row.localToGlobal(Offset.zero).dy;
  // Reversed timelines need the inverse displacement.
  final corrected = (controller.position.pixels - (y - anchor.$2)).clamp(
    0.0,
    controller.position.maxScrollExtent,
  );
  if ((corrected - controller.offset).abs() > .1) controller.jumpTo(corrected);
}
