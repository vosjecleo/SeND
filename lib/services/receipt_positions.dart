/// Merge independent public receipt streams by timeline position, not by map
/// overwrite order or the reader's device clock. Unknown events cannot prove
/// that a loaded message was read.
Set<String> readersAtOrBeyond({
  required int eventIndex,
  required Map<String, int> eventPositions,
  required Iterable<Map<String, String>> streams,
  String? ownUserId,
}) => {
  for (final stream in streams)
    for (final entry in stream.entries)
      if (entry.key != ownUserId &&
          eventPositions[entry.value] != null &&
          eventPositions[entry.value]! <= eventIndex)
        entry.key,
};
