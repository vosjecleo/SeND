import 'dart:convert';

import 'package:html/parser.dart' as html;

/// Copies message content, never room keys, event envelopes or relationships.
Map<String, dynamic> forwardedMessageContent(Map<String, dynamic> original) {
  const types = {
    'm.text',
    'm.notice',
    'm.emote',
    'm.image',
    'm.video',
    'm.audio',
    'm.file',
  };
  if (!types.contains(original['msgtype']) || original['body'] is! String) {
    throw StateError('This message cannot be forwarded.');
  }
  const fields = {
    'msgtype',
    'body',
    'format',
    'formatted_body',
    'url',
    'file',
    'info',
    'filename',
    'm.spoiler',
    'page.codeberg.everypizza.msc4193.spoiler',
    'net.send.animated',
    'net.deltie.send.gif_id',
    'net.deltiecord.gif_source',
    'org.matrix.msc3245.voice',
    'org.matrix.msc1767.audio',
  };
  final content = <String, dynamic>{
    for (final key in fields)
      if (original.containsKey(key)) key: original[key],
    // Do not notify the destination's members about an old mention.
    'm.mentions': <String, dynamic>{},
  };
  if (original['m.relates_to'] is Map &&
      (original['m.relates_to'] as Map)['m.in_reply_to'] != null) {
    final body = content['body'] as String;
    if (body.startsWith('> ') && body.contains('\n\n')) {
      content['body'] = body.substring(body.indexOf('\n\n') + 2);
    }
    if (content['formatted_body'] is String) {
      final fragment = html.parseFragment(content['formatted_body'] as String);
      for (final reply in fragment.querySelectorAll('mx-reply')) {
        reply.remove();
      }
      content['formatted_body'] = fragment.outerHtml;
    }
  }
  if (const {
    'm.image',
    'm.video',
    'm.audio',
    'm.file',
  }.contains(content['msgtype'])) {
    final file = content['file'];
    final reference = file is Map ? file['url'] : content['url'];
    final uri = reference is String ? Uri.tryParse(reference) : null;
    if (uri == null ||
        !{'mxc', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        (file != null && uri.scheme != 'mxc')) {
      throw StateError('This attachment is no longer available.');
    }
    if (file != null &&
        (file is! Map ||
            file['key'] is! Map ||
            file['iv'] is! String ||
            file['hashes'] is! Map)) {
      throw StateError('This attachment is missing its encryption details.');
    }
  }
  // SDK sending mutates maps. Do not mutate the source or its nested file keys.
  return jsonDecode(jsonEncode(content)) as Map<String, dynamic>;
}

class ForwardingFailure implements Exception {
  const ForwardingFailure(this.sent, this.total);
  final int sent, total;
}
