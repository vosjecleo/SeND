import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/video_preparation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final draft = AttachmentDraft(
    bytes: Uint8List.fromList([1, 2, 3]),
    name: 'clip.mp4',
    mimeType: 'video/mp4',
    spoiler: true,
    caption: 'Keep me',
  );
  for (final choice in VideoRecovery.values) {
    test('failed compression waits for explicit ${choice.name}', () async {
      var attempts = 0;
      final preparation = VideoPreparation(
        supported: true,
        optimizer: (value, {required progress, required canceled}) async {
          if (++attempts == 1) throw StateError('Codec unavailable');
          return value;
        },
      );
      final operation = preparation.prepare(draft);
      // Attach the failure handler before canceling, avoiding unhandled errors.
      final expected = choice == VideoRecovery.cancel
          ? expectLater(operation, throwsStateError)
          : expectLater(operation, completion(same(draft)));
      await Future<void>.delayed(Duration.zero);
      expect(preparation.active, isTrue);
      expect(preparation.failure, 'Codec unavailable');
      expect(attempts, 1);
      preparation.recover(choice);
      await expected;
      expect(preparation.active, isFalse);
      expect(preparation.failure, isNull);
      expect(attempts, choice == VideoRecovery.retry ? 2 : 1);
      preparation.dispose();
    });
  }
  test('cancel during compression never offers an original upload', () async {
    late VideoPreparation preparation;
    preparation = VideoPreparation(
      supported: true,
      optimizer: (value, {required progress, required canceled}) async {
        preparation.cancel();
        throw StateError('Video preparation canceled.');
      },
    );
    await expectLater(preparation.prepare(draft), throwsStateError);
    expect(preparation.active, isFalse);
    expect(preparation.failure, isNull);
    preparation.dispose();
  });
}
