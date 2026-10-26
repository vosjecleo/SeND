import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/services/personal_data.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/personal_organisation.dart';
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  _Backend(this.data) {
    data.addListener(notifyListeners);
  }
  final PersonalData data;
  @override
  PersonalData get personalData => data;
  @override
  List<RoomSummary> get archivedRooms =>
      roomList.where((r) => data.archived(r.id)).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'space folders expand in the rail; ordering and restoring use personal data',
    (tester) async {
      final data = PersonalData(account: '@me:test', write: (_, _) async {});
      await data.open({});
      addTearDown(data.close);
      final backend = _Backend(data)
        ..spaceList = const [
          SpaceSummary(id: 'a', name: 'Alpha'),
          SpaceSummary(id: 'b', name: 'Beta'),
        ]
        ..roomList = const [
          RoomSummary(
            id: 'r',
            name: 'Archived friend',
            lastMessage: '',
            unreadCount: 2,
            usesChannelIcon: false,
          ),
        ];
      await data.set('folder:f', 'Friends');
      await data.set('folderOf:a', 'f');
      await data.set('archive:r', true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpaceFolderRail(
              backend: backend,
              itemBuilder: (space) => Text(space.name),
            ),
          ),
        ),
      );
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
      await tester.tap(find.byTooltip('Friends (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(
        find.byTooltip('Organise spaces and archived chats'),
        findsNothing,
      );
      showPersonalOrganisation(
        tester.element(find.byType(SpaceFolderRail)),
        backend,
      );
      await tester.pumpAndSettle();
      final reorder = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      reorder.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect(data.spaceOrder, ['b', 'a']);
      await tester.ensureVisible(find.byTooltip('Restore chat'));
      await tester.tap(find.byTooltip('Restore chat'));
      await tester.pumpAndSettle();
      expect(data.archived('r'), false);
      expect(backend.roomList.single.id, 'r');
      await tester.pumpWidget(const SizedBox());
      await data.close();
    },
  );
}
