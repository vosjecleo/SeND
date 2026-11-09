import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/attachment_admission.dart';
import 'package:deltiecord/ui/large_upload_warning.dart';
import 'support/fake_backend.dart';

class _LargeBackend extends FakeBackend {
  final data = Uint8List(attachmentWarningThreshold + 1);
  int uploads = 0;
  bool compressSmall = false;
  @override
  Future<List<AttachmentDraft>> prepareAttachmentsForSend(
    List<AttachmentDraft> files, {
    void Function(int, String, double?)? onProgress,
  }) async => files
      .map(
        (file) => file.copyWith(
          bytes: compressSmall ? Uint8List(1) : data,
          mimeType: 'application/octet-stream',
        ),
      )
      .toList();
  @override
  Future<void> sendAttachment(
    AttachmentDraft file, {
    String? roomId,
    String? replyToMessageId,
  }) async => uploads++;
}

void main() {
  AttachmentDraft file() => AttachmentDraft(
    bytes: Uint8List(1),
    name: 'test.apk',
    mimeType: 'application/octet-stream',
    spoiler: false,
  );
  test('warning uses prepared bytes and declining uploads nothing', () async {
    final backend = _LargeBackend();
    addTearDown(backend.dispose);
    var warnings = 0;
    await expectLater(
      backend.submitComposerMessage(
        roomId: '!r:test',
        text: 'caption',
        attachments: [file()],
        confirmLargeUpload: (files) async {
          warnings++;
          expect(files.single.bytes.length, attachmentWarningThreshold + 1);
          return false;
        },
      ),
      throwsA(isA<LargeUploadCancelled>()),
    );
    expect(warnings, 1);
    expect(backend.uploads, 0);
  });
  test('accepting warning allows the prepared upload', () async {
    final backend = _LargeBackend();
    addTearDown(backend.dispose);
    await backend.submitComposerMessage(
      roomId: '!r:test',
      text: '',
      attachments: [file()],
      confirmLargeUpload: (_) async => true,
    );
    expect(backend.uploads, 1);
  });
  test('compression below the warning threshold does not prompt', () async {
    final backend = _LargeBackend()..compressSmall = true;
    addTearDown(backend.dispose);
    var warnings = 0;
    await backend.submitComposerMessage(
      roomId: '!r:test',
      text: '',
      attachments: [file().copyWith(bytes: backend.data)],
      confirmLargeUpload: (_) async {
        warnings++;
        return false;
      },
    );
    expect(warnings, 0);
    expect(backend.uploads, 1);
  });
  testWidgets('large-upload warning offers cancel and explicit send', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await confirmLargeUpload(context, [file()]),
            child: const Text('Open warning'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open warning'));
    await tester.pumpAndSettle();
    expect(find.text('Large upload'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, false);
    await tester.tap(find.text('Open warning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send anyway'));
    await tester.pumpAndSettle();
    expect(result, true);
  });
}
