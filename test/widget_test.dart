import 'package:deltiecord/app.dart';
import 'package:deltiecord/backend/chat_backend.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows login controls when signed out', (tester) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('Deltiecord'), findsOneWidget);
    expect(find.text('Homeserver'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('shows joined rooms and opens a timeline', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello there',
          unreadCount: 2,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('general'), findsOneWidget);
    await tester.tap(find.text('general'));
    await tester.pump();

    expect(backend.selectedRoom?.id, '!general:example.org');
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('selects a Matrix Space from the server bar', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie Club'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.byTooltip('Deltie Club'), findsOneWidget);
    await tester.tap(find.byTooltip('Deltie Club'));
    await tester.pump();

    expect(backend.selectedSpaceId, '!space:example.org');
    expect(find.text('Deltie Club'), findsOneWidget);
  });
}

class FakeBackend extends ChatBackend {
  SessionStatus currentStatus = SessionStatus.starting;
  List<RoomSummary> roomList = const [];
  RoomSummary? currentRoom;
  List<SpaceSummary> spaceList = const [];
  String? currentSpaceId;

  @override
  String? get error => null;
  @override
  List<ChatMessage> get messages => const [];
  @override
  List<RoomSummary> get rooms => roomList;
  @override
  List<SpaceSummary> get spaces => spaceList;
  @override
  String? get selectedSpaceId => currentSpaceId;
  @override
  RoomSummary? get selectedRoom => currentRoom;
  @override
  SessionStatus get status => currentStatus;
  @override
  bool get timelineLoading => false;
  @override
  String? get userId => '@deltie:example.org';

  @override
  Future<void> initialize() async {}
  @override
  void clearError() {}
  @override
  void selectSpace(String? spaceId) {
    currentSpaceId = spaceId;
    currentRoom = null;
    notifyListeners();
  }

  @override
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<void> selectRoom(String roomId) async {
    currentRoom = roomList.firstWhere((room) => room.id == roomId);
    notifyListeners();
  }

  @override
  Future<void> sendMessage(String text) async {}
}
