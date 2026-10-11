import 'package:deltiecord/ui/plain_message_editor.dart';

import 'package:deltiecord/app.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:super_clipboard/super_clipboard.dart' show DataReader;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

Future<void> pumpMobile(WidgetTester tester, FakeBackend backend) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 900);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
  );
  await tester.pumpAndSettle();
}

Future<void> enterComposer(WidgetTester tester, String text) async {
  final editor = tester.widget<PlainMessageEditor>(
    find.byType(PlainMessageEditor),
  );
  editor.controller.document = Document()..insert(0, text);
  editor.controller.updateSelection(
    TextSelection.collapsed(offset: text.length),
    ChangeSource.local,
  );
  await tester.pump();
}

Future<void> revealMessageActions(WidgetTester tester, Finder message) async {
  final mouse = await tester.createGesture(
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await mouse.addPointer();
  final position = tester.getCenter(message);
  await mouse.moveTo(position);
  await mouse.down(position);
  await mouse.up();
  await tester.pump();
  await mouse.moveTo(Offset.zero);
  await tester.pump();
  await mouse.removePointer();
}

class TestDropSession extends DropSession {
  TestDropSession(List<DataFormat> formats) : items = [_TestDropItem(formats)];
  final ended = ChangeNotifier();
  @override
  final List<DropItem> items;
  @override
  Listenable get onDisposed => ended;
  @override
  Set<DropOperation> get allowedOperations => {DropOperation.copy};
}

class _TestDropItem extends DropItem {
  _TestDropItem(this.formats);
  final List<DataFormat> formats;
  @override
  bool canProvide(DataFormat format) => formats.contains(format);
  @override
  DataReader? get dataReader => null;
  @override
  Object? get localData => null;
  @override
  List<PlatformFormat> get platformFormats => const [];
}
