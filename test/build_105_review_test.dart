import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/spoiler_reveals.dart';
import 'package:deltiecord/ui/message_metadata.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/mobile/mobile_media.dart';
import 'widget_test.dart' show FakeBackend;

const attachment = ChatAttachment(
  kind: AttachmentKind.image,
  name: 'secret.png',
  mimeType: 'image/png',
  size: 1,
  encrypted: true,
  spoiler: true,
  width: 800,
  height: 400,
);
ChatMessage message(String id, {ChatAttachment? media, String body = ''}) =>
    ChatMessage(
      id: id,
      sender: 'Alice',
      senderId: '@alice:test',
      body: body,
      timestamp: DateTime(2026, 9, 24),
      pending: false,
      own: true,
      attachment: media,
    );

void main() {
  testWidgets('an older scale callback cannot restore an earlier theme', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    final oldSlider = tester.widget<Slider>(
      find.byKey(const Key('interface-scale-slider')),
    );
    await tester.tap(find.byKey(const Key('theme-chooser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(backend.preferences.themeMode, DeltiecordThemeMode.light);
    oldSlider.onChanged!(1.1);
    await tester.pump();
    expect(backend.preferences.themeMode, DeltiecordThemeMode.light);
    expect(backend.preferences.interfaceScale, 1.1);
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      Duration.zero,
    );
  });
  testWidgets('short and long day labels stay centred with equal edge lines', (
    tester,
  ) async {
    for (final date in [DateTime.now(), DateTime(2026, 1, 1)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(width: 600, child: MessageDaySeparator(date: date)),
          ),
        ),
      );
      final label = find.descendant(
        of: find.byType(MessageDaySeparator),
        matching: find.byType(Text),
      );
      final dividers = find.byType(Divider);
      expect(
        tester.getCenter(label).dx,
        closeTo(tester.getCenter(find.byType(MessageDaySeparator)).dx, .01),
      );
      expect(
        tester.getSize(dividers.first).width,
        closeTo(tester.getSize(dividers.last).width, .01),
      );
      expect(
        tester.getTopLeft(dividers.first).dx,
        closeTo(
          tester.getTopLeft(find.byType(MessageDaySeparator)).dx + 14,
          .01,
        ),
      );
      expect(
        tester.getTopRight(dividers.last).dx,
        closeTo(
          tester.getTopRight(find.byType(MessageDaySeparator)).dx - 14,
          .01,
        ),
      );
    }
  });
  test(
    'spoiler reveals survive updates but not logout or a different session',
    () {
      final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
      final reveals = SpoilerReveals.forBackend(backend)..reveal('secret');
      backend.notifyListeners();
      expect(SpoilerReveals.forBackend(backend).contains('secret'), isTrue);
      expect(
        SpoilerReveals.forBackend(FakeBackend()).contains('secret'),
        isFalse,
      );
      backend.currentStatus = SessionStatus.signedOut;
      backend.notifyListeners();
      expect(reveals.contains('secret'), isFalse);
    },
  );
  testWidgets(
    'mobile spoiler is an opaque metadata-sized cover, without media',
    (tester) async {
      final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: Scaffold(
            body: MobileAttachmentView(
              backend: backend,
              message: message('secret', media: attachment),
            ),
          ),
        ),
      );
      final cover = find
          .descendant(
            of: find.byType(MobileAttachmentView),
            matching: find.byType(Container),
          )
          .first;
      final size = tester.getSize(cover);
      expect(size.width / size.height, closeTo(2, .001));
      final container = tester.widget<Container>(cover);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color!.a, 1);
      expect(find.byType(Image), findsNothing);
    },
  );
  testWidgets(
    'crowded media receipt moves to group header without reducing its width',
    (tester) async {
      late ReceiptPlacementScope placement;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: ReceiptPlacement(
                messages: [
                  message('media', media: attachment),
                  message('header', body: 'Hello'),
                ],
                receiptIds: const {'media'},
                contentInset: 80,
                child: Builder(
                  builder: (context) {
                    placement = ReceiptPlacementScope.of(context)!;
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(placement.relocated, contains('media'));
      expect(placement.headers['header']!.single.id, 'media');
    },
  );
  testWidgets('day separators fit narrow layouts at large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: SizedBox(
              width: 180,
              child: MessageDaySeparator(date: DateTime(2026, 8, 16)),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'mobile appearance updates immediately without waiting for a theme ticker',
    (tester) async {
      final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
      await tester.pumpWidget(
        DeltiecordApp(
          backend: backend,
          platformOverride: TargetPlatform.android,
        ),
      );
      for (final mode in [
        DeltiecordThemeMode.light,
        DeltiecordThemeMode.night,
        DeltiecordThemeMode.regular,
      ]) {
        await backend.updatePreferences(
          backend.preferences.copyWith(themeMode: mode, fontScale: 1.2),
        );
        await tester.pump();
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.themeAnimationDuration, Duration.zero);
        final field = find.byType(TextField).first;
        final context = tester.element(field);
        expect(
          Theme.of(context).brightness,
          mode == DeltiecordThemeMode.light
              ? Brightness.light
              : Brightness.dark,
        );
        expect(MediaQuery.textScalerOf(context).scale(10), 12);
      }
    },
  );
}
