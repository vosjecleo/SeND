import 'dart:async';
import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/image_preparation.dart';
import 'package:deltiecord/ui/video_preparation_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'image preparation uses the same top-level progress surface as video',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VideoPreparationOverlay(
            child: Scaffold(
              body: Text('Conversation', key: Key('conversation')),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byKey(const Key('conversation')));
      final gate = Completer<AttachmentDraft>();
      final preparation = ImagePreparation.instance.track(
        'photo.jpg',
        () => gate.future,
      );
      await tester.pump();
      expect(find.text('Optimizing photo.jpg'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('conversation'))), before);
      gate.complete(
        AttachmentDraft(
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List(4),
          spoiler: false,
        ),
      );
      await preparation;
      await tester.pump();
      expect(find.text('Optimizing photo.jpg'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('cancelling image compression cannot upload its later result', () async {
    final state = ImagePreparation(), gate = Completer<AttachmentDraft>();
    final result = state.track('photo.jpg', () => gate.future);
    final rejected = expectLater(result, throwsStateError);
    state.cancel();
    gate.complete(
      AttachmentDraft(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List(4),
        spoiler: false,
      ),
    );
    await rejected;
    expect(state.active, isFalse);
    state.dispose();
  });
}
