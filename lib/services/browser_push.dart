import 'dart:async';
import 'dart:convert';
import 'package:matrix/matrix.dart';
import 'browser_lifecycle.dart';
import 'browser_private_store.dart';
import 'bounded_http.dart';
import 'chat_notifications.dart';
import 'platform_io.dart';

const _appId = 'net.deltie.deltiecord.web';

Future<void> disableRegisteredBrowserPush(Client client) async {
  final key = await BrowserPrivateStore.read('pushkey');
  if (key != null) {
    await client.deletePusher(PusherId(appId: _appId, pushkey: key));
  }
  await disableBrowserPush();
  await BrowserPrivateStore.write('pushkey', null);
}

/// The gateway receives a short-lived Matrix OpenID proof, never the session's
/// Matrix access token. Push payloads contain event IDs, not decrypted messages.
Future<void> enableBrowserPush(Client client) async {
  // Must be first: iOS permission prompts require the original user gesture.
  final subscription = await subscribeBrowserPush();
  final userId = client.userID;
  if (userId == null) {
    throw StateError('Sign in before enabling notifications.');
  }
  final proof = await client.requestOpenIdToken(userId, const {});
  final http = HttpClient();
  try {
    final request = await http.postUrl(Uri.base.resolve('/api/push/subscribe'));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'subscription': jsonDecode(subscription),
        'openid': proof.toJson(),
        'previous': await BrowserPrivateStore.read('pushkey'),
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = await readBoundedResponse(response, maximumBytes: 8192);
    if (response.statusCode != 200) {
      throw StateError(
        'Could not register browser notifications (${response.statusCode}).',
      );
    }
    final data = jsonDecode(utf8.decode(bytes)) as Map;
    final pushkey = data['pushkey'];
    if (pushkey is! String || pushkey.length > 256 || pushkey.isEmpty) {
      throw const FormatException('Invalid push registration response.');
    }
    await client.postPusher(
      Pusher(
        appId: _appId,
        pushkey: pushkey,
        appDisplayName: 'Deltiecord',
        deviceDisplayName: 'Deltiecord Web',
        kind: 'http',
        lang: 'en',
        profileTag: 'deltiecord-web-${client.deviceID}',
        data: PusherData(
          url: Uri.base.resolve('/api/push/_matrix/push/v1/notify'),
          format: 'event_id_only',
        ),
      ),
      append: true,
    );
    final previous = await BrowserPrivateStore.read('pushkey');
    await BrowserPrivateStore.write('pushkey', pushkey);
    setBrowserPushLease(pushkey);
    if (previous != null && previous != pushkey) {
      await client.deletePusher(PusherId(appId: _appId, pushkey: previous));
    }
  } finally {
    http.close(force: true);
  }
}

class BrowserChatNotificationSink extends SilentChatNotificationSink {
  @override
  Future<void> initialize() async {
    final key = await BrowserPrivateStore.read('pushkey');
    if (key != null) setBrowserPushLease(key);
    await clearBrowserNotifications('');
  }

  @override
  Stream<NotificationTarget> get activations => browserNotificationClicks
      .where((data) => data['room_id']?.isNotEmpty == true)
      .map(
        (data) => NotificationTarget(
          roomId: data['room_id']!,
          eventId: data['event_id'] ?? '',
        ),
      );
  @override
  Future<void> clearRoom(String roomId) => clearBrowserNotifications(roomId);
  @override
  Future<void> clearPrivateState() async {
    await disableBrowserPush();
    await BrowserPrivateStore.write('pushkey', null);
  }
}
