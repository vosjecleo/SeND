import 'package:deltiecord/services/android_push_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:deltiecord/services/avatar_media_pool.dart';

class _InviterRoom extends InvitedRoom {
  _InviterRoom() : super(Membership.invite);
  @override
  Event? getState(String type, [String key = '']) =>
      type == EventTypes.RoomMember
      ? Event.fromJson({
          'type': type,
          'sender': '@inviter:example.org',
          'state_key': key,
          'content': {'membership': 'invite'},
          'event_id': r'$invite',
          'origin_server_ts': 1,
        }, this)
      : null;
}

class _ProfileClient extends InviteClient {
  _ProfileClient(super.room);
  String? requested;
  @override
  Future<CachedProfileInformation> getUserProfile(
    String userId, {
    Duration timeout = const Duration(seconds: 30),
    Duration maxCacheAge = const Duration(days: 1),
  }) async {
    requested = userId;
    return CachedProfileInformation.fromProfile(
      ProfileInformation(avatarUrl: Uri.parse('mxc://example.org/inviter')),
      outdated: false,
      updated: DateTime.now(),
    );
  }
}

class _UnreadRoom extends Fake implements Room {
  _UnreadRoom(this.pushRuleState);
  @override
  final PushRuleState pushRuleState;
  @override
  int get notificationCount => 2;
  @override
  int get highlightCount => 0;
}

class InviteClient extends Fake implements Client {
  final Room room;
  InviteClient(this.room);
  @override
  bool isLogged() => true;
  @override
  Future<void> oneShotSync({Duration? timeout}) async {}
  @override
  Room? getRoomById(String roomId) => room;
  @override
  String get userID => '@test:example.org';
  @override
  String get deviceID => 'TEST';
  @override
  Map<String, BasicEvent> get accountData => {};
  @override
  Future<Map<String, Object?>> getAccountData(
    String userId,
    String type,
  ) async => {};
}

class InvitedRoom extends Fake implements Room {
  @override
  final Membership membership;
  InvitedRoom(this.membership);
  @override
  String get id => '!invite:example.org';
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => 'Invitation';
  // Fetching history, decrypting, or accessing unread counters fails the test:
  // an invited member is not entitled to joined-room history.
}

class _HeadlessClient extends InviteClient {
  _HeadlessClient() : super(InvitedRoom(Membership.invite));
  PresenceType? _presence;
  @override
  PresenceType? get syncPresence => _presence;
  @override
  set syncPresence(PresenceType? value) => _presence = value;
  final initializedWith = <PresenceType?>[];
  int disposed = 0;
  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    disposed++;
  }

  @override
  set backgroundSync(bool value) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #init) {
      initializedWith.add(syncPresence);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  test(
    'all-message notifications use the notification count, including groups',
    () {
      expect(notificationUnreadCount(_UnreadRoom(PushRuleState.notify)), 2);
      expect(
        notificationUnreadCount(_UnreadRoom(PushRuleState.mentionsOnly)),
        0,
      );
      expect(notificationUnreadCount(_UnreadRoom(PushRuleState.dontNotify)), 0);
    },
  );
  test(
    'invitation avatar comes from the authenticated inviter, not the room',
    () async {
      final client = _ProfileClient(_InviterRoom());
      final pool = AvatarMediaPool();
      final Uint8List bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      pool.seed(
        Uri.parse('mxc://example.org/inviter'),
        bytes,
        AvatarMediaPool.rowDimension,
      );
      addTearDown(() => pool.clear(disk: false));
      final notification = await resolveAndroidPushNotification(
        client,
        '!invite:example.org',
        r'$invite',
        avatarPool: pool,
      );
      expect(client.requested, '@inviter:example.org');
      expect(notification!['senderAvatar'], same(bytes));
    },
  );
  test(
    'headless notification client opts out of online presence before init',
    () async {
      final client = _HeadlessClient();
      final resolver = HeadlessAndroidPushResolver(
        createClient: () async => client,
      );
      await resolver.resolve('!invite:example.org', r'$event');
      expect(client.initializedWith, [PresenceType.offline]);
      await resolver.close();
      expect(client.disposed, 1);
      await resolver.close();
      expect(client.disposed, 1);
      expect(client.syncPresence, PresenceType.offline);
    },
  );
  test(
    'authenticated pending invite resolves without history or unread count',
    () async {
      final result = await resolveAndroidPushNotification(
        InviteClient(InvitedRoom(Membership.invite)),
        '!invite:example.org',
        r'$event',
      );
      expect(result?['unreadCount'], 1);
      expect(result?['eventId'], r'$event');
      expect(result?['resolutionStatus'], isNull);
    },
  );
  test('stale push cannot turn a left room into an invitation', () async {
    final result = await resolveAndroidPushNotification(
      InviteClient(InvitedRoom(Membership.leave)),
      '!invite:example.org',
      r'$event',
    );
    expect(result?['resolutionStatus'], 'event_unavailable');
  });

  test(
    'invitation push has unread target and respects sound/vibration choices',
    () {
      final result = invitationNotification(
        roomId: '!room:test',
        eventId: r'$invite',
        roomName: 'A room',
        settings: {
          'notification_sound': false,
          'notification_vibration': false,
        },
      );
      expect(result['roomId'], '!room:test');
      expect(result['eventId'], r'$invite');
      expect(result['unreadCount'], 1);
      expect(result['sound'], false);
      expect(result['vibrate'], false);
    },
  );
}
