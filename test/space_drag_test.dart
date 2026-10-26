import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/services/space_organisation.dart';
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
  List<SpaceSummary> get spaces {
    final list = super.spaces.toList(),
        ids = [...data.spaceOrder, ...super.spaces.map((s) => s.id)];
    list.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));
    return list;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<PersonalData> data() async {
    final d = PersonalData(account: '@me:test', write: (_, _) async {});
    await d.open({});
    addTearDown(d.close);
    return d;
  }

  test(
    'dropping spaces creates a folder; edge drops reorder and move out',
    () async {
      final d = await data();
      final folder = await dropSpace(
        d,
        ['a', 'b', 'c'],
        const SpaceDragItem.space('a'),
        const SpaceDragItem.space('b'),
        SpaceDropPosition.inside,
      );
      expect(folder, isNotNull);
      expect(d.folderFor('a'), folder);
      expect(d.folderFor('b'), folder);
      expect(d.spaceOrder, ['b', 'a', 'c']);
      await dropSpace(
        d,
        d.spaceOrder,
        SpaceDragItem.space('a', parentFolder: folder),
        const SpaceDragItem.space('c'),
        SpaceDropPosition.after,
      );
      expect(d.folderFor('a'), isNull);
      expect(d.spaceOrder, ['b', 'c', 'a']);
      await dropSpace(
        d,
        d.spaceOrder,
        const SpaceDragItem.space('c'),
        SpaceDragItem.folder(folder!),
        SpaceDropPosition.inside,
      );
      expect(d.folderFor('c'), folder);
    },
  );
  testWidgets('hold then move creates a folder without the hold menu', (
    tester,
  ) async {
    final d = await data();
    var menus = 0, taps = 0;
    final backend = _Backend(d)
      ..spaceList = const [
        SpaceSummary(id: 'a', name: 'A'),
        SpaceSummary(id: 'b', name: 'B'),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 80,
              child: ListenableBuilder(
                listenable: backend,
                builder: (context, _) => SpaceFolderRail(
                  backend: backend,
                  onSpaceMenu: (_, _) => menus++,
                  itemBuilder: (s) => InkWell(
                    onTap: () => taps++,
                    child: SizedBox(width: 64, height: 64, child: Text(s.name)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final a = find.byKey(const ValueKey('space-drag-space:a')),
        b = find.byKey(const ValueKey('space-drop-space:b'));
    final target = tester.getCenter(b);
    final gesture = await tester.startGesture(tester.getCenter(a));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(menus, 0);
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 1));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(d.folderFor('a'), isNotNull);
    expect(d.folderFor('a'), d.folderFor('b'));
    expect(menus, 0);
    expect(taps, 0);
    expect(find.byTooltip('Organise spaces and archived chats'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await d.close();
  });
  testWidgets('a stationary hold still opens the server menu', (tester) async {
    final d = await data();
    var menus = 0;
    final backend = _Backend(d)
      ..spaceList = const [SpaceSummary(id: 'a', name: 'A')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpaceFolderRail(
            backend: backend,
            onSpaceMenu: (_, _) => menus++,
            itemBuilder: (s) => InkWell(
              onTap: () {},
              child: const SizedBox(width: 64, height: 64),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.byKey(const ValueKey('space-drag-space:a')));
    await tester.pump();
    expect(menus, 1);
    expect(d.folders, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await d.close();
  });
}
