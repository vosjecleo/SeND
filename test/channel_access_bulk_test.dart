import 'package:deltiecord/models/space_administration.dart';
import 'package:deltiecord/ui/room_access_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  final updated = <String>[];
  @override
  Future<RoomAccessSettings> getRoomAccessSettings(String roomId) async =>
      RoomAccessSettings(
        roomId: roomId,
        joinRule: roomId == '!private' ? 'invite' : 'restricted',
        historyVisibility: 'shared',
        discoverable: false,
        defaultChannelAccess: 'restricted',
        canEditAccess: true,
        canEditHistory: true,
        canEditPolicy: true,
      );
  @override
  Future<void> setRoomAccess(
    String roomId,
    String joinRule, {
    String? spaceId,
  }) async {
    updated.add(roomId);
  }
}

Future<void> _open(WidgetTester tester, _Backend backend) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRoomAccessDialog(
              context,
              backend,
              '!space',
              isSpace: true,
              children: const [
                AdministrationRoom(
                  id: '!public',
                  name: 'General',
                  powerLevels: {},
                  canEdit: true,
                ),
                AdministrationRoom(
                  id: '!private',
                  name: 'Staff',
                  powerLevels: {},
                  canEdit: true,
                ),
              ],
            ),
            child: const Text('Open access'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open access'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Apply access to existing channels…'));
  await tester.tap(find.text('Apply access to existing channels…'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'bulk access excludes private channels unless explicitly selected',
    (tester) async {
      final backend = _Backend();
      await _open(tester, backend);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'General'),
            )
            .value,
        true,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Staff'),
            )
            .value,
        false,
      );
      expect(backend.updated, isEmpty);
      await tester.tap(find.text('Apply to 1 channel'));
      await tester.pumpAndSettle();
      expect(backend.updated, ['!public']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('selecting a private channel shows its impact before any write', (
    tester,
  ) async {
    final backend = _Backend();
    await _open(tester, backend);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Staff'));
    await tester.pumpAndSettle();
    expect(
      find.text('This changes access to 1 invite-only channel.'),
      findsOneWidget,
    );
    expect(backend.updated, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Apply to 2 channels'));
    await tester.pumpAndSettle();
    expect(backend.updated, ['!public', '!private']);
  });
}
