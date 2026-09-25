/// Safe machine-readable failure, without URLs, tokens or raw server messages.
class ActivityServiceError implements Exception {
  const ActivityServiceError(this.code, {this.retryAfter});
  final String code;
  final Duration? retryAfter;
}
