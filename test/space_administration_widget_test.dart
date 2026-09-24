import 'package:deltiecord/models/space_administration.dart';
import 'package:deltiecord/ui/space_administration_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

class _AdministrationBackend extends FakeBackend {
  SpaceRoles? saved;
  final applied = <String>[];
  @override
  Future<SpaceAdministration> getSpaceAdministration(String spaceId) async =>
      SpaceAdministration(
        roles:
            saved ??
            const SpaceRoles(
              roles: [SpaceRole(id: 'member', name: 'Member', powerLevel: 0)],
              members: {},
            ),
        rooms: const [
          AdministrationRoom(
            id: '!space',
            name: 'Space',
            powerLevels: {},
            canEdit: true,
          ),
          AdministrationRoom(
            id: '!channel',
            name: 'General',
            powerLevels: {},
            canEdit: true,
          ),
        ],
        members: const {'@alice:example.org': 'Alice'},
        canEditRoles: true,
        ownPower: 100,
      );
  @override
  Future<void> saveSpaceRoles(String spaceId, SpaceRoles roles) async {
    saved = roles;
  }

  @override
  Future<void> applySpaceRolePower(
    String spaceId,
    String roomId,
    SpaceRoles reviewedRoles,
  ) async {
    if (roomId == '!channel') throw StateError('Not permitted');
    applied.add(roomId);
  }
}

void main() {
  testWidgets(
    'administration separates metadata save from explicit permission propagation',
    (tester) async {
      final backend = _AdministrationBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpaceAdministrationPanel(
                backend: backend,
                spaceId: '!space',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save roles'));
      await tester.tap(find.text('Save roles'));
      await tester.pumpAndSettle();
      expect(backend.saved!.members['@alice:example.org'], {'member'});
      expect(backend.applied, isEmpty);
      await tester.ensureVisible(find.text('Also apply to child rooms'));
      await tester.tap(find.text('Also apply to child rooms'));
      await tester.pumpAndSettle();
      final apply = find.text('Apply saved role power to selected rooms');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(backend.applied, isEmpty);
      await tester.tap(find.text('Apply').last);
      await tester.pumpAndSettle();
      expect(backend.applied, ['!space']);
      expect(find.textContaining('Applied to 1/2.'), findsOneWidget);
      expect(
        find.textContaining('Successful changes were not rolled back.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
