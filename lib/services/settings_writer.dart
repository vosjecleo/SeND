import 'dart:async';

/// Owns settings debounce, serialization and cancellation. Resetting a session
/// invalidates queued work and lets the next account start without waiting for
/// an old network request. The write callback must also guard its async result.
final class SettingsWriter<T extends Object> {
  SettingsWriter({
    required this.write,
    required this.changed,
    this.delay = const Duration(milliseconds: 300),
  });
  final Future<void> Function(T) write;
  final void Function() changed;
  final Duration delay;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  T? _pending;
  T? get pending => _pending;
  int _generation = 0;
  bool _disposed = false;

  void request(T value) {
    if (_disposed) return;
    _pending = value;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  Future<void> flush() {
    _timer?.cancel();
    final value = _pending, generation = _generation;
    if (_disposed || value == null) return Future<void>.value();
    final next = _queue.then((_) async {
      if (_disposed ||
          generation != _generation ||
          !identical(value, _pending)) {
        return;
      }
      try {
        await write(value);
        if (!_disposed &&
            generation == _generation &&
            identical(value, _pending)) {
          _pending = null;
          changed();
        }
      } catch (_) {
        // The backend reports the write error. Retain the local choice for an
        // explicit retry or newer edit, without an unbounded retry loop.
      }
    });
    _queue = next;
    return next;
  }

  void reset() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _queue = Future<void>.value();
  }

  void dispose() {
    reset();
    _disposed = true;
  }
}
