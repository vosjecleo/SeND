import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/emoji_repository.dart';
import 'package:deltiecord/services/settings_echo_guard.dart';
import 'package:deltiecord/ui/theme_chooser.dart';
import 'package:deltiecord/ui/message_metadata.dart';
import 'package:deltiecord/ui/emoji_typography.dart';
import 'widget_test.dart' show FakeBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'primary shortcodes beat incidental keywords; sobbing stays an alias',
    () async {
      final repository = EmojiRepository.instance;
      for (final pair in {
        'grinning': '😀',
        'smile': '😄',
        'confounded': '😖',
        'sob': '😭',
        'sobbing': '😭',
      }.entries) {
        expect((await repository.exactAlias(pair.key))?.emoji, pair.value);
      }
      expect(
        (await repository.search('cheerful')).any((e) => e.emoji == '😀'),
        isTrue,
      );
      final entries = await repository.load();
      expect(entries.every((e) => e.shortcode.isNotEmpty), isTrue);
      expect(
        entries.firstWhere((e) => e.emoji == '😖').shortcode,
        'confounded',
      );
    },
  );
  test('late settings echoes cannot replace local choices', () {
    final guard = SettingsEchoGuard();
    guard.expect({'theme': 'light'}, {'theme': 'dark'});
    guard.expect({'theme': 'light'}, {'theme': 'night'});
    expect(guard.accepts({'theme': 'light'}), isFalse);
    expect(guard.accepts({'theme': 'dark'}), isFalse);
    expect(guard.accepts({'theme': 'night'}), isTrue);
    expect(guard.accepts({'theme': 'light'}), isTrue);
    guard.expect({'theme': 'light'}, {'theme': 'dark'});
    expect(
      guard.accepts({'theme': 'gray'}),
      isTrue,
      reason: 'Allow a new edit from another device',
    );
  });
  test('emoji style excludes inherited outline font and bold weight', () {
    final style = colourEmojiStyle(
      const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
    );
    expect(style.fontFamily, isNot('monospace'));
    expect(style.fontWeight, FontWeight.normal);
    expect(style.fontFamilyFallback, contains('Noto Color Emoji'));
  });
  testWidgets('theme chooser is one row and fits a narrow scaled screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var value = DeltiecordThemeMode.regular;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: Scaffold(
            body: ThemeChooser(value: value, onChanged: (v) => value = v),
          ),
        ),
      ),
    );
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.byKey(const Key('theme-chooser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night'));
    await tester.pumpAndSettle();
    expect(value, DeltiecordThemeMode.night);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'media receipt stays immediately right of media, not in a new row',
    (tester) async {
      final message = ChatMessage(
        id: 'media',
        sender: 'Me',
        body: '',
        timestamp: DateTime(2026),
        own: true,
        pending: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MediaWithMessageMetadata(
                message: message,
                showReceipt: true,
                child: const SizedBox(
                  key: Key('image'),
                  width: 100,
                  height: 80,
                ),
              ),
            ),
          ),
        ),
      );
      final media = tester.getRect(find.byKey(const Key('image')));
      final receipt = tester.getRect(find.byIcon(Icons.check));
      expect(receipt.left, greaterThan(media.right));
      expect(receipt.left - media.right, lessThan(12));
      expect(receipt.bottom, lessThanOrEqualTo(media.bottom));
      expect(tester.widget<Icon>(find.byIcon(Icons.check)).size, 10);
    },
  );
  testWidgets('theme and scale update repeatedly without a resume event', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    for (var i = 0; i < 5; i++) {
      await backend.updatePreferences(
        backend.preferences.copyWith(
          themeMode: i.isEven
              ? DeltiecordThemeMode.light
              : DeltiecordThemeMode.night,
          fontScale: i.isEven ? 1.3 : 1,
        ),
      );
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.theme!.brightness,
        i.isEven ? Brightness.light : Brightness.dark,
      );
      final field = find.byType(TextField).first;
      expect(
        MediaQuery.textScalerOf(tester.element(field)).scale(10),
        i.isEven ? 13 : 10,
      );
    }
  });
}
