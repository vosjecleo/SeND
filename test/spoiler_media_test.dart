import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/spoiler_reveals.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/mobile/mobile_media.dart';
import 'support/fake_backend.dart';

void main() {
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
}

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
