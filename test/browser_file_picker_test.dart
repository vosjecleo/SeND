@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:deltiecord/services/browser_file_picker.dart';

void main() {
  test(
    'browser attachments read File bytes without fetching blob URLs',
    () async {
      final pending = pickBrowserAttachments(accept: 'image/*,video/*');
      final input =
          web.document.querySelector('input[type=file]')!
              as web.HTMLInputElement;
      final files = web.DataTransfer();
      files.items.add(
        web.File(
          [
            Uint8List.fromList([1, 2, 3]).toJS,
          ].toJS,
          'note.txt',
          web.FilePropertyBag(type: 'text/plain'),
        ),
      );
      input.files = files.files;
      input.dispatchEvent(web.Event('change'));
      final selected = await pending;
      expect(selected.single.bytes, [1, 2, 3]);
      expect(selected.single.name, 'note.txt');
      expect(selected.single.mimeType, 'text/plain');
      expect(web.document.querySelector('input[type=file]'), isNull);
    },
  );

  test('cancel cleans up the camera input', () async {
    final pending = pickBrowserAttachments(accept: 'image/*', camera: true);
    final input =
        web.document.querySelector('input[type=file]')! as web.HTMLInputElement;
    expect(input.getAttribute('capture'), 'environment');
    expect(input.multiple, false);
    input.dispatchEvent(web.Event('cancel'));
    expect(await pending, isEmpty);
    expect(web.document.querySelector('input[type=file]'), isNull);
  });
}
