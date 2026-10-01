@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/browser_image_paste.dart';

web.ClipboardEvent imagePaste() {
  final data = web.DataTransfer();
  data.items.add(
    web.File(
      [
        Uint8List.fromList([137, 80, 78, 71]).toJS,
      ].toJS,
      'image.png',
      web.FilePropertyBag(type: 'image/png'),
    ),
  );
  return web.ClipboardEvent(
    'paste',
    web.ClipboardEventInit(
      clipboardData: data,
      bubbles: true,
      cancelable: true,
    ),
  );
}

void main() {
  test(
    'gesture image bytes are consumed, text paste remains untouched',
    () async {
      final received = Completer<List<AttachmentDraft>>();
      final remove = listenBrowserImagePaste(
        enabled: () => true,
        onImages: received.complete,
        onError: (e) => fail(e),
      );
      addTearDown(remove);
      final text = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(cancelable: true),
      );
      web.document.dispatchEvent(text);
      expect(text.defaultPrevented, false);
      final paste = imagePaste();
      web.document.dispatchEvent(paste);
      expect(paste.defaultPrevented, true);
      final drafts = await received.future;
      expect(drafts.single.name, 'image.png');
      expect(drafts.single.bytes, [137, 80, 78, 71]);
    },
  );

  test(
    'focus and room changes cannot paste into a different composer',
    () async {
      var enabled = false;
      var room = 'a';
      var count = 0;
      final remove = listenBrowserImagePaste(
        enabled: () => enabled,
        contextKey: () => room,
        onImages: (_) => count++,
        onError: (e) => fail(e),
      );
      addTearDown(remove);
      final ignored = imagePaste();
      web.document.dispatchEvent(ignored);
      expect(ignored.defaultPrevented, false);
      enabled = true;
      web.document.dispatchEvent(imagePaste());
      room = 'b';
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(count, 0);
    },
  );
}
