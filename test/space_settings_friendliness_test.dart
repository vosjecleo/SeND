import 'dart:async';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/space_administration.dart';
import 'package:deltiecord/ui/space_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  bool admin = true;
  int selections = 0, profileLoads = 0;
  Completer<SpaceProfileOverride?>? profileGate;
  Completer<SpaceJoinResult>? joinGate;
  @override
  Future<SpaceJoinResult> joinAvailableSpaceChannels(String spaceId) =>
      joinGate?.future ?? Future.value(const SpaceJoinResult());
  final renamed = <String>[];
  @override
  bool canChangeRoomState(String roomId, String type) =>
      admin && roomId == '!target:test';
  @override
  bool canManageSpaceChannelLayout(String spaceId) => admin;
  @override
  void selectSpace(String? id) {
    selections++;
    super.selectSpace(id);
  }

  @override
  List<RoomSummary> roomsInSpace(String spaceId) => roomList;
  @override
  List<ChannelCategorySummary> categoriesInSpace(String spaceId) =>
      categoryList;
  @override
  Future<SpaceProfileOverride?> getSpaceProfileOverride(String id) async {
    profileLoads++;
    return await profileGate?.future;
  }

  @override
  Future<void> renameRoom(String id, String name) async {
    renamed.add('$id/$name');
  }

  @override
  Future<RoomAccessSettings> getRoomAccessSettings(String id) async =>
      RoomAccessSettings(
        roomId: id,
        joinRule: 'invite',
        historyVisibility: 'shared',
        discoverable: false,
        canEditAccess: admin,
        canEditHistory: admin,
        canEditPolicy: admin,
      );
}

const _space = SpaceSummary(id: '!target:test', name: 'Target server');

Future<void> _open(WidgetTester tester, _Backend backend) async {
  tester.view.physicalSize = const Size(1400, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  backend.currentStatus = SessionStatus.signedIn;
  await tester.pumpWidget(DeltiecordApp(backend: backend));
  await tester.pumpAndSettle();
  unawaited(
    showSpaceSettings(
      tester.element(find.byType(Scaffold).first),
      backend,
      _space,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('channel catch-up does not lock the settings window open', (
    tester,
  ) async {
    final backend = _Backend()..joinGate = Completer<SpaceJoinResult>();
    await _open(tester, backend);
    await tester.tap(find.text('My notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join available channels'));
    await tester.pump();
    final close = find.widgetWithText(ListTile, 'Close');
    await tester.scrollUntilVisible(
      close,
      80,
      scrollable: find
          .descendant(
            of: find.byType(Dialog).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    backend.joinGate!.complete(const SpaceJoinResult());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'opening server settings does not change the current space or fetch profiles',
    (tester) async {
      final backend = _Backend()..currentSpaceId = '!other:test';
      await _open(tester, backend);
      expect(backend.selectedSpaceId, '!other:test');
      expect(backend.selections, 0);
      expect(backend.profileLoads, 0);
      expect(find.byKey(const Key('space-settings-name')), findsOneWidget);
      expect(find.text('My settings'), findsOneWidget);
      expect(find.text('Manage server'), findsOneWidget);
    },
  );
  testWidgets(
    'ordinary members see their own settings, not editable server forms',
    (tester) async {
      final backend = _Backend()..admin = false;
      await _open(tester, backend);
      expect(find.text('Manage server'), findsNothing);
      expect(find.byKey(const Key('space-settings-name')), findsNothing);
      expect(
        find.text('Automatically join accessible channels'),
        findsOneWidget,
      );
      expect(find.text('Server profile'), findsOneWidget);
    },
  );
  testWidgets('unsaved overview edits require a choice before changing page', (
    tester,
  ) async {
    final backend = _Backend();
    await _open(tester, backend);
    await tester.enterText(
      find.byKey(const Key('space-settings-name')),
      'Unsaved name',
    );
    await tester.tap(find.text('Channels'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('space-settings-name')))
          .controller!
          .text,
      'Unsaved name',
    );
    expect(backend.renamed, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    expect(backend.renamed, ['!target:test/Unsaved name']);
    await tester.tap(find.text('Channels'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(find.text('Create channel'), findsOneWidget);
    expect(find.text('Create category'), findsOneWidget);
  });
  testWidgets('late profile failure does not block another settings page', (
    tester,
  ) async {
    final backend = _Backend()
      ..profileGate = Completer<SpaceProfileOverride?>();
    await _open(tester, backend);
    await tester.tap(find.text('Server profile'));
    await tester.pump();
    await tester.tap(find.text('My notifications'));
    await tester.pumpAndSettle();
    backend.profileGate!.completeError(StateError('Synthetic profile failure'));
    await tester.pumpAndSettle();
    expect(find.text('Automatically join accessible channels'), findsOneWidget);
    expect(
      find.text(
        'Could not load settings. Check your connection and try again.',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
