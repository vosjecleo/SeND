import 'dart:async';
import 'package:flutter/foundation.dart';
import 'activity_service_error.dart';

/// Device-owned, expiring profile metadata. No device model or identifier is
/// published in the value, and a background notification cannot renew it.
class MobilePresencePublisher extends ChangeNotifier {
  MobilePresencePublisher({
    required this.write,
    required this.enabled,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final Future<void> Function(Map<String, Object?>?) write;
  final bool Function() enabled;
  final DateTime Function() now;
  Timer? _timer;
  Future<void>? _operation;
  DateTime? _renewAt, _retryAt;
  bool _published = false, _closed = false, _again = false;
  bool get active => !_closed && _published && enabled();

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  Future<void> refresh() {
    if (_closed) return Future.value();
    if (_operation case final running?) {
      _again = true;
      return running;
    }
    return _operation = _publish().whenComplete(() {
      _operation = null;
      if (_again && !_closed) {
        _again = false;
        unawaited(refresh());
      }
    });
  }

  Future<void> _publish() async {
    final desired = enabled();
    final time = now();
    if (_retryAt != null && time.isBefore(_retryAt!)) return;
    if (desired == _published &&
        (!desired || (_renewAt != null && time.isBefore(_renewAt!)))) {
      return;
    }
    try {
      await write(
        desired
            ? {
                'version': 1,
                'mobile': true,
                'expires_at': time
                    .add(const Duration(minutes: 2))
                    .millisecondsSinceEpoch,
              }
            : null,
      ).timeout(const Duration(seconds: 10));
      _published = desired;
      _retryAt = null;
      _renewAt = time.add(const Duration(seconds: 55));
      if (!_closed) notifyListeners();
      if (desired != enabled()) _again = true;
    } catch (error) {
      _retryAt = time.add(
        error is ActivityServiceError
            ? error.retryAfter ?? const Duration(seconds: 30)
            : const Duration(seconds: 30),
      );
    }
  }

  Future<void> close({bool clear = false}) async {
    _closed = true;
    _timer?.cancel();
    await _operation;
    if (clear && _published) {
      try {
        await write(null).timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    dispose();
  }
}
