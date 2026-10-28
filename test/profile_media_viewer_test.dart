import 'dart:async';
import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/profile_card.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/image_zoom_viewer.dart';
import 'package:deltiecord/ui/profile_media_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  final png = Uint8List.fromList(
    image.encodePng(image.Image(width: 4, height: 4)),
  );
  testWidgets(
    'viewer keeps its preview while the original loads, with zoom and close controls',
    (tester) async {
      final original = Completer<Uint8List?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showProfileMedia(context, png, () => original.future),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.byType(ImageZoomViewer), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      original.complete(png);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip('Close viewer'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageZoomViewer), findsNothing);
    },
  );
  testWidgets('profile media opens on demand, crop previews remain editable', (
    tester,
  ) async {
    var loads = 0;
    final profile = UserProfileSummary(
      userId: '@a:test',
      displayName: 'Alice',
      avatarBytes: png,
      bannerBytes: png,
    );
    Widget card(bool preview) => MaterialApp(
      theme: ThemeData(
        extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
      ),
      home: Scaffold(
        body: SizedBox(
          width: 350,
          child: DeltiecordProfileCard(
            profile: profile,
            preview: preview,
            loadImage: (banner) async {
              loads++;
              return png;
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(false));
    await tester.pumpAndSettle();
    expect(loads, 0);
    await tester.tap(find.bySemanticsLabel('View avatar'));
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.tap(find.byTooltip('Close viewer'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('View banner'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    await tester.tap(find.byTooltip('Close viewer'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(card(true));
    expect(find.bySemanticsLabel('View avatar'), findsNothing);
    expect(find.bySemanticsLabel('View banner'), findsNothing);
  });
}
