import 'package:html/parser.dart' as html;

bool hasMessageWebLink(String body, String? formatted) {
  if (RegExp(r'https?://', caseSensitive: false).hasMatch(body)) return true;
  if (formatted == null) return false;
  final fragment = html.parseFragment(formatted);
  for (final reply in fragment.querySelectorAll('mx-reply')) {
    reply.remove();
  }
  return fragment.querySelectorAll('a[href]').any((a) {
    final uri = Uri.tryParse(a.attributes['href'] ?? '');
    return uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.host != 'matrix.to';
  });
}
