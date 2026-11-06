import 'package:deltiecord/services/message_forwarding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text keeps formatting but not original relationships or mentions', () {
    final result = forwardedMessageContent({
      'msgtype': 'm.text',
      'body': '> <@someone:test> private quote\n\nHello **there**',
      'format': 'org.matrix.custom.html',
      'formatted_body':
          '<mx-reply><blockquote>private quote</blockquote></mx-reply>Hello <strong>there</strong>',
      'm.relates_to': {
        'm.in_reply_to': {'event_id': r'$secret'},
        'rel_type': 'm.thread',
      },
      'm.mentions': {
        'room': true,
        'user_ids': ['@someone:test'],
      },
      'm.new_content': {'body': 'not the displayed content'},
      'transaction_id': 'old transaction',
    });
    expect(result['body'], 'Hello **there**');
    expect(result['formatted_body'], 'Hello <strong>there</strong>');
    expect(result['m.mentions'], isEmpty);
    expect(result.containsKey('m.relates_to'), false);
    expect(result.containsKey('m.new_content'), false);
    expect(result.containsKey('transaction_id'), false);
  });
  test('a literal quote without a reply relationship stays unchanged', () {
    final result = forwardedMessageContent({
      'msgtype': 'm.text',
      'body': '> quoted\n\ntext',
    });
    expect(result['body'], '> quoted\n\ntext');
  });
  for (final type in ['m.image', 'm.video', 'm.audio', 'm.file']) {
    test('$type reuses unchanged ciphertext and thumbnail descriptors', () {
      final file = {
        'url': 'mxc://test/media',
        'key': {'k': 'attachment-key', 'kty': 'oct'},
        'iv': 'original-iv',
        'hashes': {'sha256': 'original-hash'},
        'v': 'v2',
      };
      final original = <String, dynamic>{
        'msgtype': type,
        'body': 'Caption',
        'filename': 'original.bin',
        'file': file,
        'info': {'w': 320, 'h': 180, 'thumbnail_file': file},
        'm.spoiler': true,
        'org.matrix.msc3245.voice': <String, dynamic>{},
      };
      final result = forwardedMessageContent(original);
      expect(result['file'], file);
      expect(result['info'], original['info']);
      expect(result['body'], 'Caption');
      expect(result['filename'], 'original.bin');
      expect(result['m.spoiler'], true);
      (result['file'] as Map)['iv'] = 'mutated';
      expect(file['iv'], 'original-iv');
    });
  }
  test('plain attachment MXC is preserved without upload', () {
    expect(
      forwardedMessageContent({
        'msgtype': 'm.image',
        'body': 'image.png',
        'url': 'mxc://test/photo',
      })['url'],
      'mxc://test/photo',
    );
  });
  test('missing references, incomplete keys and unsupported events fail', () {
    for (final content in <Map<String, dynamic>>[
      {'msgtype': 'm.image', 'body': 'missing'},
      {
        'msgtype': 'm.image',
        'body': 'bad',
        'file': {'url': 'mxc://test/photo'},
      },
      {'msgtype': 'm.file', 'body': 'bad', 'url': 'file:///secret'},
      {
        'msgtype': 'm.image',
        'body': 'bad',
        'file': {'url': 'https://test/photo'},
      },
      {'msgtype': 'm.poll', 'body': 'poll'},
    ]) {
      expect(() => forwardedMessageContent(content), throwsStateError);
    }
  });
}
