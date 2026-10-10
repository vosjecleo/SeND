import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/mobile/mobile_media.dart';
import 'widget_test.dart' show FakeBackend;

class _Backend extends FakeBackend {
  final downloads = <bool>[];
  final playback = Completer<MediaPlaybackSource?>();
  var opens = 0;
  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async {
    downloads.add(thumbnail);
    return image.encodePng(image.Image(width: 2, height: 2));
  }

  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) {
    opens++;
    return playback.future;
  }
}

void main() {
  testWidgets(
    'mobile video uses its poster and metadata before requesting playback',
    (tester) async {
      final backend = _Backend();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: Scaffold(
            body: MobileAttachmentView(
              backend: backend,
              message: ChatMessage(
                id: 'video',
                sender: 'Test',
                body: '',
                timestamp: DateTime(2026),
                pending: false,
                attachment: const ChatAttachment(
                  kind: AttachmentKind.video,
                  name: 'clip.mp4',
                  mimeType: 'video/mp4',
                  size: 20 * 1024 * 1024,
                  encrypted: true,
                  spoiler: false,
                  width: 480,
                  height: 360,
                  hasThumbnail: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(backend.downloads, [true]);
      expect(backend.opens, 0);
      expect(find.byType(Image), findsOneWidget);
      final frame = tester.getSize(find.byType(Image));
      expect(frame.width / frame.height, closeTo(4 / 3, .001));
      await tester.tap(find.byTooltip('Play video'));
      await tester.pump();
      expect(backend.opens, 1);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      backend.playback.complete(null);
      await tester.pump();
    },
  );
}
