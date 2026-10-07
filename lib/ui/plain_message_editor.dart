import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show QuillController, ChangeSource;

import '../backend/chat_backend.dart';
import '../services/custom_emoji.dart';
import 'composer_emoji_span.dart';
import 'rich_message.dart';

/// Plain text input. The legacy document is only a draft/emoji-offset codec;
/// no rich editor, automatic formatting, HTML paste or formatting shortcuts.
class PlainMessageEditor extends StatefulWidget {
  const PlainMessageEditor({
    required this.controller,
    required this.backend,
    required this.focusNode,
    required this.scrollController,
    required this.enabled,
    required this.onPasteImage,
    required this.onKeyEvent,
    required this.padding,
    required this.style,
    required this.hintStyle,
    required this.placeholder,
    super.key,
  });
  final QuillController controller;
  final ChatBackend backend;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final bool enabled;
  final Future<bool> Function() onPasteImage;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final EdgeInsets padding;
  final TextStyle style, hintStyle;
  final String placeholder;
  @override
  State<PlainMessageEditor> createState() => _PlainMessageEditorState();
}

class _PlainMessageEditorState extends State<PlainMessageEditor> {
  late final _PlainController _text;
  bool _syncing = false;
  @override
  void initState() {
    super.initState();
    _text = _PlainController(widget.controller, widget.backend);
    _fromDocument();
    _text.addListener(_toDocument);
    widget.controller.addListener(_fromDocument);
  }

  void _fromDocument() {
    if (_syncing) return;
    _syncing = true;
    try {
      final source = widget.controller.document.toPlainText();
      final text = source.endsWith('\n')
          ? source.substring(0, source.length - 1)
          : source;
      final selection = widget.controller.selection;
      _text.value = TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: selection.baseOffset.clamp(0, text.length),
          extentOffset: selection.extentOffset.clamp(0, text.length),
        ),
      );
    } finally {
      _syncing = false;
    }
  }

  void _toDocument() {
    if (_syncing) return;
    _syncing = true;
    try {
      final source = widget.controller.document.toPlainText();
      reconcileRichMessageDocument(
        widget.controller.document,
        source.substring(0, source.length - 1),
        _text.text,
      );
      widget.controller.updateSelection(_text.selection, ChangeSource.local);
    } finally {
      _syncing = false;
    }
    // Emoji/mention completion can synchronously update the document in response.
    // Keep IME composing ranges intact unless completion actually changed text.
    if (widget.controller.document.toPlainText() != '${_text.text}\n') {
      _fromDocument();
    }
  }

  Future<void> _paste() async {
    if (!widget.enabled || await widget.onPasteImage() || !mounted) return;
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || clipboard?.text == null) return;
    final value = _text.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : start;
    final inserted = clipboard!.text!;
    _text.value = TextEditingValue(
      text: value.text.replaceRange(start, end, inserted),
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_fromDocument);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: widget.onKeyEvent,
    child: Actions(
      actions: {
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (_) {
            _paste();
            return null;
          },
        ),
      },
      child: TextField(
        key: const ValueKey('plain-message-editor'),
        controller: _text,
        inputFormatters: [CustomEmojiDeletionFormatter(widget.controller)],
        focusNode: widget.focusNode,
        scrollController: widget.scrollController,
        enabled: widget.enabled,
        minLines: null,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textAlignVertical: TextAlignVertical.center,
        style: widget.style,
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding: widget.padding,
          hintText: widget.placeholder,
          hintStyle: widget.hintStyle,
        ),
        contextMenuBuilder: (context, state) =>
            AdaptiveTextSelectionToolbar.buttonItems(
              anchors: state.contextMenuAnchors,
              buttonItems: state.contextMenuButtonItems
                  .map(
                    (item) => item.type == ContextMenuButtonType.paste
                        ? ContextMenuButtonItem(
                            type: ContextMenuButtonType.paste,
                            onPressed: () {
                              state.hideToolbar();
                              _paste();
                            },
                          )
                        : item,
                  )
                  .toList(),
            ),
      ),
    ),
  );
}

/// A displayed custom emoji is one editing unit, not its hidden shortcode.
class CustomEmojiDeletionFormatter extends TextInputFormatter {
  CustomEmojiDeletionFormatter(this.controller);
  final QuillController controller;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length >= oldValue.text.length ||
        !newValue.composing.isCollapsed ||
        !oldValue.composing.isCollapsed ||
        controller.document.toPlainText() != '${oldValue.text}\n') {
      return newValue;
    }
    var start = 0;
    while (start < newValue.text.length &&
        oldValue.text[start] == newValue.text[start]) {
      start++;
    }
    var suffix = 0;
    while (suffix < newValue.text.length - start &&
        oldValue.text[oldValue.text.length - 1 - suffix] ==
            newValue.text[newValue.text.length - 1 - suffix]) {
      suffix++;
    }
    if (start + suffix != newValue.text.length) return newValue;
    var end = oldValue.text.length - suffix;
    final cursor = oldValue.selection.extentOffset;
    final removed = oldValue.text.length - newValue.text.length;
    if (oldValue.selection.isCollapsed &&
        cursor >= removed &&
        oldValue.text.replaceRange(cursor - removed, cursor, '') ==
            newValue.text) {
      start = cursor - removed;
      end = cursor;
    }
    var offset = 0;
    for (final op in controller.document.toDelta().toJson()) {
      final text = op['insert'];
      if (text is! String) continue;
      final next = offset + text.length;
      final link = (op['attributes'] as Map?)?['link'] as String?;
      if (customEmojiFromEditorLink(link) != null) {
        for (final token in RegExp(r':[^:\s]+:').allMatches(text)) {
          final tokenStart = offset + token.start;
          final tokenEnd = offset + token.end;
          if (tokenStart < end && tokenEnd > start) {
            start = start < tokenStart ? start : tokenStart;
            end = end > tokenEnd ? end : tokenEnd;
          }
        }
      }
      offset = next;
    }
    end = end.clamp(start, oldValue.text.length);
    return TextEditingValue(
      text: oldValue.text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }
}

class _PlainController extends TextEditingController {
  _PlainController(this.document, this.backend);
  final QuillController document;
  final ChatBackend backend;
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (value.composing.isValid && !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final children = <InlineSpan>[];
    var offset = 0;
    for (final op in document.document.toDelta().toJson()) {
      final inserted = op['insert'];
      if (inserted is! String || offset >= text.length) continue;
      final end = (offset + inserted.length).clamp(0, text.length);
      children.add(
        composerEmojiSpan(
          backend: backend,
          text: text.substring(offset, end),
          link: (op['attributes'] as Map?)?['link'] as String?,
          style: style,
        ),
      );
      offset = end;
    }
    return TextSpan(style: style, children: children);
  }
}
