import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';
import 'support/rtc_wire_fixture.dart' show wireClient, jsonResponse;

Map<String, Object?> event(
  String id,
  DateTime time,
  Map<String, Object?> content, {
  int ttl = 60000,
  String type = rtcStickyMemberType,
}) => {
  'event_id': id,
  'type': type,
  'sender': '@friend:example.org',
  'origin_server_ts': time.millisecondsSinceEpoch,
  'content': content,
  'unsigned': {'msc4354_sticky_duration_ttl_ms': ttl},
};
Map<String, Object?> syncEvents(List<Map<String, Object?>> events) => {
  'next_batch': 'batch',
  'rooms': {
    'join': {
      '!room:example.org': {
        'msc4354_sticky': {'events': events},
      },
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = RtcTransport(url: Uri.parse('wss://sfu.example.org'));
  Map<String, Object?> membership({bool leave = false}) => rtcStickyMembership(
    userId: '@friend:example.org',
    deviceId: 'OTHER',
    memberId: 'member',
    transport: transport,
    leave: leave,
  );

  test(
    'one sync preserves the SDK cursor, filters and offline presence',
    () async {
      var count = 0;
      final now = DateTime.now();
      final client = await wireClient((request) async {
        count++;
        expect(request.url.path, '/_matrix/client/v3/sync');
        expect(request.url.queryParameters, {
          'filter': 'filter-id',
          'since': 'previous',
          'set_presence': 'offline',
          'timeout': '30000',
        });
        expect(
          request.headers['authorization'],
          'Bearer public-session-fixture',
        );
        return jsonResponse(syncEvents([event('join', now, membership())]));
      });
      addTearDown(client.dispose);
      final response = await client.sync(
        filter: 'filter-id',
        since: 'previous',
        setPresence: PresenceType.offline,
        timeout: 30000,
      );
      expect(response.nextBatch, 'batch');
      expect(count, 1);
      final room = Room(id: '!room:example.org', client: client);
      expect((await client.hydrateRtcMembers(room)).single.deviceId, 'OTHER');
    },
  );

  test(
    'state and sticky memberships both retain their wire timestamps',
    () async {
      final client = await wireClient(
        (_) async => jsonResponse({'next_batch': 'batch'}),
      );
      addTearDown(client.dispose);
      final now = DateTime.now();
      final data = syncEvents([event('sticky', now, membership())]);
      final join =
          ((data['rooms'] as Map)['join'] as Map)['!room:example.org'] as Map;
      join['state'] = {
        'events': [
          {
            'type': rtcCallMemberType,
            'state_key': '_@legacy:example.org_DEVICE_m.call',
            'sender': '@legacy:example.org',
            'event_id': 'state',
            'origin_server_ts': now.millisecondsSinceEpoch,
            'content': rtcStateMembership(
              userId: '@legacy:example.org',
              deviceId: 'DEVICE',
              createdAt: now,
              transport: transport,
            )..remove('created_ts'),
          },
        ],
      };
      client.retainRtcExtensions(data);
      expect(
        client.rtcStateMembers('!room:example.org').single.userId,
        '@legacy:example.org',
      );
      expect(
        (await client.hydrateRtcMembers(
          Room(id: '!room:example.org', client: client),
        )).single.userId,
        '@friend:example.org',
      );
    },
  );

  test(
    'a newer leave wins over a late older join, including after expiry',
    () async {
      final client = await wireClient(
        (_) async => jsonResponse({'next_batch': 'batch'}),
      );
      addTearDown(client.dispose);
      final room = Room(id: '!room:example.org', client: client);
      final now = DateTime.now();
      client.retainRtcExtensions(
        syncEvents([event('join', now, membership())]),
      );
      expect(await client.hydrateRtcMembers(room), hasLength(1));
      client.retainRtcExtensions(
        syncEvents([
          event(
            'leave',
            now.add(const Duration(milliseconds: 1)),
            membership(leave: true),
            ttl: 200,
          ),
        ]),
      );
      expect(await client.hydrateRtcMembers(room), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      client.retainRtcExtensions(
        syncEvents([event('older-join', now, membership())]),
      );
      expect(await client.hydrateRtcMembers(room), isEmpty);
    },
  );

  test(
    'duplicate deliveries never extend sticky lifetime; ignored events stay out',
    () async {
      final client = await wireClient(
        (_) async => jsonResponse({'next_batch': 'batch'}),
      );
      addTearDown(client.dispose);
      final now = DateTime.now();
      final message = event('same', now, membership());
      client.retainRtcExtensions(syncEvents([message]), receivedAt: now);
      client.retainRtcExtensions(
        syncEvents([
          message,
          event('ordinary', now, {}, type: EventTypes.Message),
          event('oversized', now, {'payload': 'x' * 40000}),
          event('bad-ttl', now, membership(), ttl: 3600001),
        ]),
        receivedAt: now.add(const Duration(seconds: 5)),
      );
      final records = client.rtcStickyEvents('!room:example.org');
      expect(records, hasLength(1));
      expect(records.single.expiresAt, now.add(const Duration(seconds: 60)));
    },
  );

  test(
    'transient RTC cache is bounded and leaving a room removes its data',
    () async {
      final client = await wireClient(
        (_) async => jsonResponse({'next_batch': 'batch'}),
      );
      addTearDown(client.dispose);
      final now = DateTime.now();
      for (var batch = 0; batch < 3; batch++) {
        client.retainRtcExtensions(
          syncEvents(
            List.generate(
              512,
              (i) => event('event-$batch-$i', now, membership()),
            ),
          ),
        );
      }
      expect(client.rtcStickyEvents('!room:example.org'), hasLength(1024));
      client.retainRtcExtensions({
        'rooms': {
          'leave': {'!room:example.org': {}},
        },
      });
      expect(client.rtcStickyEvents('!room:example.org'), isEmpty);
      expect(client.cachedRtcMembers('!room:example.org'), isEmpty);
    },
  );
  test(
    'state membership cache has a global bound and rejects oversized events',
    () async {
      final client = await wireClient((_) async => jsonResponse({}));
      addTearDown(client.dispose);
      final now = DateTime.now();
      Map<String, Object?> state(int index) => {
        'type': rtcCallMemberType,
        'sender': '@friend:example.org',
        'state_key': rtcMembershipStateKey(
          '@friend:example.org',
          'DEVICE$index',
        ),
        'origin_server_ts': now.millisecondsSinceEpoch,
        'content': rtcStateMembership(
          userId: '@friend:example.org',
          deviceId: 'DEVICE$index',
          createdAt: now,
          transport: transport,
        ),
      };
      for (var room = 0; room < 3; room++) {
        client.retainRtcExtensions({
          'rooms': {
            'join': {
              '!room$room:example.org': {
                'state': {'events': List.generate(512, state)},
              },
            },
          },
        });
      }
      expect(
        List.generate(
          3,
          (room) => client.rtcStateMembers('!room$room:example.org').length,
        ).reduce((a, b) => a + b),
        lessThanOrEqualTo(1024),
      );
      final huge = state(999);
      (huge['content'] as Map)['padding'] = List.filled(40000, 'x').join();
      client.retainRtcExtensions({
        'rooms': {
          'join': {
            '!huge:example.org': {
              'state': {
                'events': [huge],
              },
            },
          },
        },
      });
      expect(client.rtcStateMembers('!huge:example.org'), isEmpty);
    },
  );
}
