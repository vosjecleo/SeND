class VideoEditPlan {
  const VideoEditPlan({
    this.startMs = 0,
    this.endMs,
    this.turns = 0,
    this.muted = false,
    this.left = 0,
    this.top = 0,
    this.width = 1,
    this.height = 1,
  });
  final int startMs, turns;
  final int? endMs;
  final bool muted;
  final double left, top, width, height;
  bool get hasChanges =>
      startMs != 0 ||
      endMs != null ||
      turns % 4 != 0 ||
      muted ||
      left != 0 ||
      top != 0 ||
      width != 1 ||
      height != 1;
  int durationMs(int original) {
    if (startMs < 0 ||
        startMs >= original ||
        (endMs != null && (endMs! > original || endMs! <= startMs)) ||
        [left, top, width, height].any((v) => !v.isFinite) ||
        left < 0 ||
        top < 0 ||
        width <= 0 ||
        height <= 0 ||
        left + width > 1.000001 ||
        top + height > 1.000001) {
      throw const FormatException('Invalid video edit range.');
    }
    return (endMs ?? original) - startMs;
  }

  Map<String, Object?> toMap() => {
    'startMs': startMs,
    if (endMs != null) 'endMs': endMs,
    'turns': turns % 4,
    'muted': muted,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}
