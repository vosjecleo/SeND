import 'dart:async';

/// Coalesces a burst into one trailing callback without postponing it forever.
/// Native callers can opt out; disposal invalidates already scheduled work.
class CoalescedCallback {
  CoalescedCallback(this.callback, {required this.enabled});
  final void Function() callback;
  final bool enabled;
  Timer? _timer;
  bool _disposed = false;

  void request() {
    if (_disposed) return;
    if (!enabled) {
      callback();
      return;
    }
    _timer ??= Timer(const Duration(milliseconds: 16), () {
      _timer = null;
      if (!_disposed) callback();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
