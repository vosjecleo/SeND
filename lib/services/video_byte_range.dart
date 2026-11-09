/// Successful status alone does not prove a seek reached the requested bytes.
bool matchesVideoByteRange({
  required String? requested,
  required int status,
  required String? contentRange,
  required int contentLength,
}) {
  final range = requested == null
      ? null
      : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(requested);
  if (requested != null &&
      (range == null || (range[1]!.isEmpty && range[2]!.isEmpty))) {
    return false;
  }
  if (status == 200) {
    return contentRange == null && (requested == null || range![1] == '0');
  }
  if (status != 206) return false;
  final response = RegExp(
    r'^bytes (\d+)-(\d+)/(\d+)$',
  ).firstMatch(contentRange?.trim() ?? '');
  if (response == null) return false;
  final start = int.tryParse(response[1]!);
  final end = int.tryParse(response[2]!);
  final total = int.tryParse(response[3]!);
  if (start == null ||
      end == null ||
      total == null ||
      total <= 0 ||
      end < start ||
      end >= total ||
      (contentLength >= 0 && contentLength != end - start + 1)) {
    return false;
  }
  if (range == null) return start == 0;
  if (range[1]!.isEmpty) {
    final suffix = int.tryParse(range[2]!);
    return suffix != null &&
        suffix > 0 &&
        end == total - 1 &&
        start == (total - suffix).clamp(0, total);
  }
  final expected = int.tryParse(range[1]!);
  final last = range[2]!.isEmpty ? null : int.tryParse(range[2]!);
  if (expected == null ||
      start != expected ||
      (range[2]!.isNotEmpty && (last == null || last < expected))) {
    return false;
  }
  return last == null || end <= last;
}
