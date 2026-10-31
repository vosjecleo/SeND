import 'package:deltiecord/services/android_push_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

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
