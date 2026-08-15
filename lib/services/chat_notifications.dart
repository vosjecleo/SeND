import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'desktop_window_service.dart';

class NotificationTarget {
  const NotificationTarget({required this.roomId, required this.eventId});

  final String roomId;
  final String eventId;
}

/// Platform boundary for notifications emitted by the Matrix backend.
abstract interface class ChatNotificationSink {
  Stream<NotificationTarget> get activations;
  Future<void> initialize();
  Future<void> show({
    required String title,
    required String body,
    required String roomId,
    required String eventId,
    bool sound = true,
  });

  Future<void> dispose();
}

class DesktopChatNotificationSink implements ChatNotificationSink {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _activations = StreamController<NotificationTarget>.broadcast();
  var _nextId = 1;
  bool _initialized = false;

  void _activatePayload(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, Object?>;
      final roomId = data['room_id'] as String?;
      final eventId = data['event_id'] as String?;
      if (roomId == null || eventId == null) return;
      _activations.add(NotificationTarget(roomId: roomId, eventId: eventId));
      unawaited(DesktopWindowService.present());
    } catch (_) {
      // Ignore stale or malformed notification payloads.
    }
  }

  @override
  Stream<NotificationTarget> get activations => _activations.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open Deltiecord',
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _activatePayload(response.payload),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _activatePayload(launch?.notificationResponse?.payload);
    }
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    required String roomId,
    required String eventId,
    bool sound = true,
  }) => _plugin.show(
    id: _nextId++,
    title: title,
    body: body,
    payload: jsonEncode({'room_id': roomId, 'event_id': eventId}),
    notificationDetails: NotificationDetails(
      linux: LinuxNotificationDetails(
        category: LinuxNotificationCategory.imReceived,
        urgency: LinuxNotificationUrgency.normal,
        suppressSound: !sound,
      ),
    ),
  );

  @override
  Future<void> dispose() => _activations.close();
}

class SilentChatNotificationSink implements ChatNotificationSink {
  const SilentChatNotificationSink();

  @override
  Stream<NotificationTarget> get activations => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required String title,
    required String body,
    required String roomId,
    required String eventId,
    bool sound = true,
  }) async {}

  @override
  Future<void> dispose() async {}
}
