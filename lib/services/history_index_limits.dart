const historyIndexMaxMiB = 2048;

/// Larger, explicitly selected byte budgets also allow more small records.
int historyIndexEntryLimit(int limitMiB) =>
    100000 * ((limitMiB + 99) ~/ 100).clamp(1, 21);
