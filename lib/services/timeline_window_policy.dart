import 'dart:math';

enum TimelinePageDirection { older, newer }

/// Applies Deltiecord's bounded moving-window rules to newest-first events.
///
/// Matrix timelines expose index zero as the newest event. Loading older
/// context therefore evicts from the beginning, while moving toward the
/// present evicts from the end. Scroll anchoring remains a UI responsibility.
abstract final class TimelineWindowPolicy {
  static int hardCap({required int chunkSize, required int chunkCap}) =>
      min(120, max(1, chunkSize) * max(1, chunkCap));

  static void trimNewestFirst<T>(
    List<T> events, {
    required int hardCap,
    required TimelinePageDirection loaded,
  }) {
    if (events.length <= hardCap) return;
    final overflow = events.length - hardCap;
    switch (loaded) {
      case TimelinePageDirection.older:
        events.removeRange(0, overflow);
      case TimelinePageDirection.newer:
        events.removeRange(hardCap, events.length);
    }
  }
}
