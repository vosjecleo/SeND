import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

/// Compact renderer for Matrix's sanitized `org.matrix.custom.html` subset.
/// Unsupported elements degrade to their text children instead of creating
/// arbitrary widgets or executing external content.
class MatrixHtmlText extends StatefulWidget {
  const MatrixHtmlText({required this.html, required this.fallback, super.key});

  final String html;
  final String fallback;

  @override
  State<MatrixHtmlText> createState() => _MatrixHtmlTextState();
}

class _MatrixHtmlTextState extends State<MatrixHtmlText> {
  late final TapGestureRecognizer _spoilerTap = TapGestureRecognizer()
    ..onTap = () => setState(() => _spoilersRevealed = true);
  final List<TapGestureRecognizer> _linkRecognizers = [];
  bool _spoilersRevealed = false;

  @override
  void dispose() {
    _spoilerTap.dispose();
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = html_parser.parseFragment(widget.html);
    final spans = _nodes(document.nodes, const TextStyle(height: 1.28));
    if (spans.isEmpty) return SelectableText(widget.fallback);
    return SelectableText.rich(TextSpan(children: spans));
  }

  List<InlineSpan> _nodes(Iterable<dom.Node> nodes, TextStyle style) =>
      nodes.expand((node) => _node(node, style)).toList(growable: false);

  List<InlineSpan> _node(dom.Node node, TextStyle style) {
    if (node is dom.Text) return [TextSpan(text: node.data, style: style)];
    if (node is! dom.Element) return const [];
    final tag = node.localName;
    if (tag == 'mx-reply') return const [];
    if (tag == 'br') return const [TextSpan(text: '\n')];
    if (node.attributes.containsKey('data-mx-spoiler') && !_spoilersRevealed) {
      return [
        TextSpan(
          text: '  SPOILER  ',
          style: style.copyWith(
            color: const Color(0xff17181c),
            backgroundColor: const Color(0xff777985),
            fontWeight: FontWeight.w600,
          ),
          recognizer: _spoilerTap,
        ),
      ];
    }

    var childStyle = style;
    switch (tag) {
      case 'strong':
      case 'b':
        childStyle = style.copyWith(fontWeight: FontWeight.bold);
      case 'em':
      case 'i':
        childStyle = style.copyWith(fontStyle: FontStyle.italic);
      case 'u':
        childStyle = style.copyWith(decoration: TextDecoration.underline);
      case 'del':
      case 's':
        childStyle = style.copyWith(decoration: TextDecoration.lineThrough);
      case 'code':
        childStyle = style.copyWith(
          fontFamily: 'monospace',
          backgroundColor: const Color(0xff191a1e),
        );
      case 'a':
        childStyle = style.copyWith(
          color: const Color(0xffaeb7ff),
          decoration: TextDecoration.underline,
        );
    }

    final children = _nodes(node.nodes, childStyle);
    if (tag == 'a') {
      final href = node.attributes['href'];
      final isMention =
          href?.contains('/#/user/@') == true ||
          node.text.trimLeft().startsWith('@');
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          final uri = href == null ? null : Uri.tryParse(href);
          if (uri != null && {'http', 'https'}.contains(uri.scheme)) {
            launchUrl(uri);
          }
        };
      _linkRecognizers.add(recognizer);
      return [
        TextSpan(
          children: children,
          style: isMention
              ? childStyle.copyWith(
                  backgroundColor: const Color(0xff3f456c),
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w600,
                )
              : childStyle,
          recognizer: recognizer,
        ),
      ];
    }
    if (tag == 'blockquote') {
      return [
        const TextSpan(
          text: '│ ',
          style: TextStyle(color: Color(0xff747fdb)),
        ),
        ...children,
        const TextSpan(text: '\n'),
      ];
    }
    if (tag == 'li') {
      return [
        const TextSpan(text: '• '),
        ...children,
        const TextSpan(text: '\n'),
      ];
    }
    if ({'p', 'div', 'pre'}.contains(tag)) {
      return [...children, const TextSpan(text: '\n')];
    }
    return children;
  }
}
