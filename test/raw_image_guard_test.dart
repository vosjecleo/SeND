import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/media_compression.dart';
import 'package:deltiecord/services/raw_image.dart';
import 'package:deltiecord/services/image_preparation.dart';
import 'package:deltiecord/services/queued_message.dart';
import 'package:deltiecord/services/video_preparation.dart';
import 'package:deltiecord/matrix/sized_matrix_file.dart';
import 'package:deltiecord/ui/attachment_image_editor.dart';
import 'package:deltiecord/ui/media_editor_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final extension in [
    'RAW',
    'dNg',
    'NEF',
    'CR2',
    'CR3',
    'ARW',
    'RAF',
    'RW2',
    'ORF',
    'PEF',
    'SRW',
    'X3F',
    '3FR',
    'IIQ',
  ]) {
    test('camera .$extension is not offered to a raster decoder', () {
      expect(
        isRawImageFile('photo.$extension', 'application/octet-stream'),
        true,
      );
    });
  }
  test('RAW MIME types are recognised without a filename extension', () {
    for (final mime in [
      'image/x-adobe-dng',
      'image/x-canon-cr2',
      'image/x-sony-arw',
      'image/raw',
    ]) {
      expect(isRawImageFile('photo', mime), true);
    }
    for (final extension in ['jpg', 'png', 'gif', 'heic', 'tiff', 'webp']) {
      expect(isRawImageFile('photo.$extension', 'image/$extension'), false);
    }
  });
  test(
    'RAW uploads remain byte-for-byte files instead of being resized',
    () async {
      final bytes = Uint8List.fromList([0x49, 0x49, 42, 0]);
      final draft = AttachmentDraft(
        bytes: bytes,
        name: 'photo.dng',
        mimeType: 'image/x-adobe-dng',
        spoiler: false,
      );
      final prepared = await prepareImage(
        draft,
        ImageCompressionPreset.balanced,
      );
      expect(prepared, same(draft));
      expect(prepared.bytes, same(bytes));
      expect(ImagePreparation.instance.active, false);
      final file = RawImageMatrixFile(
        bytes: bytes,
        name: draft.name,
        mimeType: draft.mimeType,
      );
      expect(file.msgType, 'm.file');
      expect(file.info['mimetype'], draft.mimeType);
      final pending = QueuedMessage(
        id: 'tx',
        room: 'room',
        body: '',
        sender: 'Me',
        senderId: '@me:test',
        draft: draft,
      );
      expect(pending.message.attachment!.kind, AttachmentKind.file);
    },
  );
  test(
    'camera containers mislabelled as video never enter a video decoder',
    () async {
      final draft = AttachmentDraft(
        bytes: Uint8List(16),
        name: 'photo.CR3',
        mimeType: 'video/mp4',
        spoiler: false,
      );
      final preparation = VideoPreparation(
        supported: true,
        optimizer: (_, {required progress, required canceled}) async =>
            throw StateError('Decoder must not be called'),
      );
      expect(await preparation.prepare(draft), same(draft));
      expect(await VideoPreparation.probe(draft), same(draft));
      expect(preparation.active, false);
      preparation.dispose();
    },
  );
  for (final mime in ['image/x-adobe-dng', 'application/octet-stream']) {
    testWidgets(
      'RAW click explains the restriction without opening an editor: $mime',
      (tester) async {
        AttachmentDraft? result;
        var returned = false;
        final draft = AttachmentDraft(
          bytes: Uint8List.fromList([0x49, 0x49, 42, 0]),
          name: 'photo.DNG',
          mimeType: mime,
          spoiler: false,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showAttachmentImageEditor(context, draft);
                    returned = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            "RAW images can't be edited. Use a tool like Lightroom or Rawtherapee.",
          ),
          findsOneWidget,
        );
        expect(find.byType(MediaEditorLayout), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Okay'));
        await tester.pumpAndSettle();
        expect(returned, true);
        expect(result, isNull);
      },
    );
  }
}
