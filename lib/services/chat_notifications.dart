import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Platform boundary for notifications emitted by the Matrix backend.
abstract interface class ChatNotificationSink {
  Future<void> initialize();
  Future<void> show({
    required String title,
    required String body,
    bool sound = true,
  });
}

class DesktopChatNotificationSink implements ChatNotificationSink {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  var _nextId = 1;

  @override
  Future<void> initialize() => _plugin.initialize(
    settings: const InitializationSettings(
      linux: LinuxInitializationSettings(defaultActionName: 'Open Deltiecord'),
    ),
  );

  @override
  Future<void> show({
    required String title,
    required String body,
    bool sound = true,
  }) => _plugin.show(
    id: _nextId++,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      linux: LinuxNotificationDetails(
        category: LinuxNotificationCategory.imReceived,
        urgency: LinuxNotificationUrgency.normal,
        suppressSound: !sound,
      ),
    ),
  );
}

class SilentChatNotificationSink implements ChatNotificationSink {
  const SilentChatNotificationSink();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required String title,
    required String body,
    bool sound = true,
  }) async {}
}
