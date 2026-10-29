/// Invalidates asynchronous work even when an SDK client object is reused for
/// another login. A lease can suppress late results, not undo a sent request.
final class SessionScope {
  int _generation = 0;
  bool _disposed = false;
  SessionLease capture() => SessionLease._(this, _generation);
  void invalidate() {
    _generation++;
  }

  void dispose() {
    invalidate();
    _disposed = true;
  }
}

final class SessionLease {
  SessionLease._(this._scope, this._generation);
  final SessionScope _scope;
  final int _generation;
  bool get isCurrent => !_scope._disposed && _generation == _scope._generation;
}
