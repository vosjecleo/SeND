import 'package:deltiecord/services/giphy_service.dart';
import 'package:deltiecord/ui/expression_picker.dart';
import 'package:deltiecord/ui/emoji_picker_dialog.dart';
import 'package:deltiecord/ui/advanced_chat_dialogs.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/mobile/mobile_attachment_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

void main() {
  testWidgets(
    'expression picker defaults to emoji and exposes sticker management',
    (tester) async {
      final backend = FakeBackend();
      final giphy = GiphyService();
      addTearDown(giphy.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExpressionPicker(context, backend, giphy),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPickerDialog), findsOneWidget);
      expect(find.text('GIFs'), findsOneWidget);
      await tester.tap(find.text('Stickers'));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPickerContents), findsOneWidget);
      expect(find.text('Create or import a pack'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'photo picker keeps camera and fallback actions without gallery access',
    (tester) async {
      const channel = MethodChannel('com.fluttercandies/photo_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => 0,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: const Scaffold(body: MobileAttachmentPicker()),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Camera', 'Picker', 'Poll', 'Files']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
