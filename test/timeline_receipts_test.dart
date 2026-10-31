import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/receipt_frontiers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/receipt_positions.dart';
import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:deltiecord/services/room_read_marker.dart';

void main() {
  test('receipt boundaries advance to latest sent and latest read', () {
    ChatMessage message(String id, {bool read = false, bool pending = false}) =>
        ChatMessage(
          id: id,
          sender: 'Me',
          body: 'hi',
          timestamp: DateTime(2026),
          own: true,
          pending: pending,
          readBy: read
              ? const [
                  ReceiptReaderSummary(
                    userId: '@friend:test',
                    displayName: 'Friend',
                  ),
                ]
              : const [],
        );
    expect(
      receiptFrontiers([
        message('pending', pending: true),
        message('new'),
        message('middle'),
        message('read', read: true),
        message('old', read: true),
      ]),
      {'new', 'read'},
    );
    expect(
      receiptFrontiers([
        message('read', read: true),
        message('old', read: true),
      ]),
      {'read'},
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('an old main-thread receipt cannot erase a newer global receipt', () {
    expect(
      readersAtOrBeyond(
        eventIndex: 1,
        eventPositions: {'new': 0, 'message': 1, 'old': 2},
        streams: [
          {'alice': 'new'},
          {'alice': 'old'},
        ],
      ),
      {'alice'},
    );
    expect(
      readersAtOrBeyond(
        eventIndex: 1,
        eventPositions: {'new': 0, 'message': 1, 'old': 2},
        streams: [
          {'alice': 'old'},
          {'alice': 'new'},
        ],
      ),
      {'alice'},
    );
  });

  test('unknown, older and own receipts do not claim a message was read', () {
    expect(
      readersAtOrBeyond(
        eventIndex: 1,
        ownUserId: 'me',
        eventPositions: {'new': 0, 'message': 1, 'old': 2},
        streams: [
          {'alice': 'missing', 'bob': 'old', 'me': 'new', 'carol': 'message'},
        ],
      ),
      {'carol'},
    );
  });

  for (final threaded in [false, true]) {
    for (final public in [false, true]) {
      test(
        'unread acknowledgement persists with public=$public, threads=$threaded',
        () async {
          final client = _Client();
          final room = Room(id: '!room:test', client: client);
          await acknowledgeRoom(
            room,
            r'$newest',
            sendPublicReceipts: public,
            mainThreadOnly: threaded,
          );
          expect(client.markers.single['fullyRead'], r'$newest');
          if (threaded) {
            expect(
              client.receipts,
              contains((ReceiptType.mReadPrivate, 'main')),
            );
            expect(
              client.receipts.contains((ReceiptType.mRead, 'main')),
              public,
            );
            expect(client.markers.single['public'], isNull);
          } else {
            expect(client.markers.single['private'], r'$newest');
            expect(client.markers.single['public'], public ? r'$newest' : null);
          }
        },
      );
    }
  }
}

class _Client extends Fake implements Client {
  final markers = <Map<String, String?>>[];
  final receipts = <(ReceiptType, String?)>[];
  @override
  bool get receiptsPublicByDefault => true;
  @override
  Future<void> setReadMarker(
    String roomId, {
    String? mFullyRead,
    String? mRead,
    String? mReadPrivate,
  }) async {
    markers.add({
      'fullyRead': mFullyRead,
      'public': mRead,
      'private': mReadPrivate,
    });
  }

  @override
  Future<void> postReceipt(
    String roomId,
    ReceiptType type,
    String eventId, {
    String? threadId,
  }) async {
    receipts.add((type, threadId));
  }
}
