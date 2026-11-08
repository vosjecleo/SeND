import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/clipboard_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var textReads = 0;
  setUp(() {
    textReads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            textReads++;
            return {'text': 'pasted'};
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  test(
    'image read starts in the paste gesture and does not paste text too',
    () async {
      final controller = TextEditingController(text: 'draft');
      addTearDown(controller.dispose);
      var started = false;
      final done = pasteComposerClipboard(
        controller: controller,
        pasteImage: () {
          started = true;
          return Future.value(true);
        },
        isCurrent: () => true,
      );
      expect(started, true);
      await done;
      expect(textReads, 0);
      expect(controller.text, 'draft');
    },
  );
  test(
    'text-only paste replaces the selection after an empty image read',
    () async {
      final controller = TextEditingController(text: 'hello world')
        ..selection = const TextSelection(baseOffset: 6, extentOffset: 11);
      addTearDown(controller.dispose);
      await pasteComposerClipboard(
        controller: controller,
        pasteImage: () async => false,
        isCurrent: () => true,
      );
      expect(controller.text, 'hello pasted');
      expect(controller.selection.baseOffset, 12);
    },
  );
  test('image permission failure still allows ordinary text paste', () async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pasteComposerClipboard(
      controller: controller,
      pasteImage: () async => throw StateError('Permission denied'),
      isCurrent: () => true,
    );
    expect(controller.text, 'pasted');
  });
  test(
    'a room switch during clipboard access cannot alter the new draft',
    () async {
      final controller = TextEditingController(text: 'new room draft');
      addTearDown(controller.dispose);
      var current = true;
      final gate = Completer<bool>();
      final done = pasteComposerClipboard(
        controller: controller,
        pasteImage: () => gate.future,
        isCurrent: () => current,
      );
      current = false;
      gate.complete(false);
      await done;
      expect(controller.text, 'new room draft');
      expect(textReads, 0);
    },
  );
}
