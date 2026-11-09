import 'dart:async';
import 'package:flutter/foundation.dart';

/// Serializes seek commands and keeps the chosen position visible until the
/// decoder acknowledges it, rather than snapping back to an old stream tick.
class VideoSeekController extends ChangeNotifier {
  VideoSeekController({
    required this.seek,
    Duration initialPosition = Duration.zero,
    Duration initialDuration = Duration.zero,
  }) : _position = initialPosition,
       _duration = initialDuration;
  final Future<void> Function(Duration) seek;
  Duration _position, _duration;
  Duration? _pending, _queued;
  Future<void>? _running;
  Timer? _deadline;
  bool _disposed = false;
  Duration get position => _pending ?? _position;
  Duration get duration => _duration;
  bool get canSeek => _duration > Duration.zero;
  bool get hasPendingSeek => _pending != null;

  void update({Duration? position, Duration? duration}) {
    if (_disposed) return;
    if (duration != null && duration > Duration.zero) _duration = duration;
    if (position != null) {
      _position = position;
      if (_pending != null &&
          (position - _pending!).inMilliseconds.abs() <= 750) {
        _pending = null;
        _deadline?.cancel();
      }
    }
    notifyListeners();
  }

  Future<void> skip(int seconds) =>
      seekTo(position + Duration(seconds: seconds));

  Future<void> seekTo(Duration target) {
    if (_disposed || !canSeek) return Future.value();
    target = Duration(
      milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    _pending = _queued = target;
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 5), () {
      if (_disposed) return;
      _pending = null;
      notifyListeners();
    });
    notifyListeners();
    return _startDrain();
  }

  Future<void> _startDrain() => _running ??= _drain().whenComplete(() {
    _running = null;
    // A gesture may arrive between the last loop check and completion.
    if (!_disposed && _queued != null) unawaited(_startDrain());
  });

  Future<void> _drain() async {
    while (!_disposed && _queued != null) {
      final target = _queued!;
      _queued = null;
      try {
        await seek(target);
      } catch (_) {
        if (!_disposed && _pending == target) {
          _pending = null;
          _deadline?.cancel();
          notifyListeners();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _queued = null;
    _deadline?.cancel();
    super.dispose();
  }
}
