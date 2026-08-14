part of 'chat_shell.dart';

class _RichComposer extends StatefulWidget {
  const _RichComposer({
    required this.controller,
    required this.focusNode,
    required this.roomName,
    required this.enabled,
    required this.onSend,
    required this.onAttach,
    required this.onGif,
    required this.onPasteImage,
    required this.pendingAttachments,
    required this.onRemoveAttachment,
    required this.onToggleAttachmentSpoiler,
    required this.mentionSuggestions,
    required this.mentionSelectionIndex,
    required this.onMentionSelected,
    required this.onMentionSelectionChanged,
  });

  final QuillController controller;
  final FocusNode focusNode;
  final String roomName;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onGif;
  final Future<bool> Function() onPasteImage;
  final List<AttachmentDraft> pendingAttachments;
  final ValueChanged<int> onRemoveAttachment;
  final ValueChanged<int> onToggleAttachmentSpoiler;
  final List<MentionSuggestion> mentionSuggestions;
  final int mentionSelectionIndex;
  final ValueChanged<String> onMentionSelected;
  final ValueChanged<int> onMentionSelectionChanged;

  @override
  State<_RichComposer> createState() => _RichComposerState();
}

class _MentionPicker extends StatelessWidget {
  const _MentionPicker({
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<MentionSuggestion> suggestions;
  final int selectedIndex;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Material(
      color: const Color(0xff202126),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Color(0xff4a4c56)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 210),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            return ListTile(
              dense: true,
              selected: index == selectedIndex,
              selectedTileColor: const Color(0xff34374b),
              title: Text(suggestion.displayName),
              subtitle: Text(suggestion.isRoom ? 'Room' : suggestion.matrixId),
              onTap: () => onSelected(suggestion.matrixId),
            );
          },
        ),
      ),
    ),
  );
}

class _RichComposerState extends State<_RichComposer> {
  final _scrollController = ScrollController();
  static const _emoji = [
    '😀',
    '😄',
    '😂',
    '🥹',
    '😍',
    '😎',
    '😭',
    '😡',
    '👍',
    '👎',
    '❤️',
    '💜',
    '🔥',
    '🎉',
    '👀',
    '✨',
    '🤔',
    '🫡',
    '🙏',
    '💀',
    '✅',
    '❌',
    '⭐',
    '🍕',
  ];

  void _insertEmoji(String emoji) {
    final selection = widget.controller.selection;
    final start = selection.start < 0
        ? widget.controller.document.length - 1
        : selection.start;
    final length = selection.isValid ? selection.end - selection.start : 0;
    widget.controller.replaceText(
      start,
      length,
      emoji,
      TextSelection.collapsed(offset: start + emoji.length),
    );
    widget.focusNode.requestFocus();
  }

  Future<void> _showEmojiPicker() async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final emoji = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx + box.size.width - 250,
        origin.dy - 180,
        10,
        0,
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: SizedBox(
            width: 210,
            child: Wrap(
              children: [
                for (final item in _emoji)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(item),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(item, style: const TextStyle(fontSize: 21)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    if (emoji != null) _insertEmoji(emoji);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 40,
          height: 34,
          child: PopupMenuButton<String>(
            tooltip: 'Add content',
            enabled: widget.enabled,
            padding: EdgeInsets.zero,
            icon: const Icon(
              Icons.add_circle_outline,
              size: 25,
              color: Color(0xffc7c8d0),
            ),
            onSelected: (action) {
              switch (action) {
                case 'file':
                  widget.onAttach();
                case 'emoji':
                  _showEmojiPicker();
                case 'gif':
                  widget.onGif();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'file',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.insert_drive_file_outlined),
                  title: Text('Add file'),
                ),
              ),
              PopupMenuItem(
                value: 'emoji',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.emoji_emotions_outlined),
                  title: Text('Emoji'),
                ),
              ),
              PopupMenuItem(
                value: 'gif',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.gif_box_outlined),
                  title: Text('Sticker / GIF'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xff777985)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.pendingAttachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (
                          var index = 0;
                          index < widget.pendingAttachments.length;
                          index++
                        )
                          _PendingAttachmentTile(
                            attachment: widget.pendingAttachments[index],
                            onRemove: () => widget.onRemoveAttachment(index),
                            onToggleSpoiler: () =>
                                widget.onToggleAttachmentSpoiler(index),
                          ),
                      ],
                    ),
                  ),
                DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 15),
                  child: QuillEditor(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    scrollController: _scrollController,
                    config: QuillEditorConfig(
                      autoFocus: false,
                      minHeight: 32,
                      maxHeight: 132,
                      customStyles: const DefaultStyles(
                        paragraph: DefaultTextBlockStyle(
                          TextStyle(fontSize: 15, height: 1.2),
                          HorizontalSpacing.zero,
                          VerticalSpacing.zero,
                          VerticalSpacing.zero,
                          null,
                        ),
                        placeHolder: DefaultTextBlockStyle(
                          TextStyle(
                            fontSize: 15,
                            height: 1.2,
                            color: Color(0x99989aa5),
                          ),
                          HorizontalSpacing.zero,
                          VerticalSpacing.zero,
                          VerticalSpacing.zero,
                          null,
                        ),
                      ),
                      // Keep the compact 32 px composer while seating its text
                      // cleanly alongside the attachment and send controls.
                      padding: const EdgeInsets.fromLTRB(12, 7, 12, 3),
                      placeholder: 'Message #${widget.roomName}',
                      // ignore: experimental_member_use
                      onKeyPressed: (event, _) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.keyV &&
                            (HardwareKeyboard.instance.isControlPressed ||
                                HardwareKeyboard.instance.isMetaPressed)) {
                          unawaited(widget.onPasteImage());
                          return KeyEventResult.ignored;
                        }
                        if (event is KeyDownEvent &&
                            widget.mentionSuggestions.isNotEmpty) {
                          if (event.logicalKey ==
                              LogicalKeyboardKey.arrowDown) {
                            widget.onMentionSelectionChanged(
                              (widget.mentionSelectionIndex + 1) %
                                  widget.mentionSuggestions.length,
                            );
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            widget.onMentionSelectionChanged(
                              (widget.mentionSelectionIndex - 1) %
                                  widget.mentionSuggestions.length,
                            );
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            widget.onMentionSelected(
                              widget
                                  .mentionSuggestions[widget
                                      .mentionSelectionIndex]
                                  .matrixId,
                            );
                            return KeyEventResult.handled;
                          }
                        }
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          widget.onSend();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 40,
          height: 34,
          child: IconButton(
            tooltip: 'Send',
            padding: EdgeInsets.zero,
            onPressed: widget.enabled ? widget.onSend : null,
            icon: const Icon(Icons.send, size: 25, color: Color(0xffc7c8d0)),
          ),
        ),
      ],
    ),
  );
}

class _PendingAttachmentTile extends StatelessWidget {
  const _PendingAttachmentTile({
    required this.attachment,
    required this.onRemove,
    required this.onToggleSpoiler,
  });

  final AttachmentDraft attachment;
  final VoidCallback onRemove;
  final VoidCallback onToggleSpoiler;

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(position);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPosition.dx, localPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'spoiler',
          child: ListTile(
            dense: true,
            leading: Icon(
              attachment.spoiler
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            title: Text(attachment.spoiler ? 'Remove spoiler' : 'Spoiler'),
          ),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.close),
            title: Text('Remove attachment'),
          ),
        ),
      ],
    );
    if (action == 'spoiler') onToggleSpoiler();
    if (action == 'remove') onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    final isVideo = attachment.mimeType.startsWith('video/');
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showMenu(context, details.globalPosition),
      child: Tooltip(
        message: '${attachment.name}\nRight-click for options',
        child: Container(
          width: 92,
          height: 68,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xff292a30),
            border: Border.all(
              color: attachment.spoiler
                  ? const Color(0xff747fdb)
                  : const Color(0xff484a53),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isImage)
                Image.memory(attachment.bytes, fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isVideo
                          ? Icons.video_file_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 23,
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ],
                ),
              if (attachment.spoiler)
                const ColoredBox(
                  color: Color(0xcc17181c),
                  child: Center(
                    child: Icon(Icons.visibility_off_outlined, size: 20),
                  ),
                ),
              Positioned(
                right: 1,
                top: 1,
                child: SizedBox.square(
                  dimension: 20,
                  child: IconButton.filledTonal(
                    padding: EdgeInsets.zero,
                    tooltip: 'Remove',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({
    required this.label,
    required this.body,
    required this.onCancel,
  });

  final String label;
  final String body;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xff202126),
    padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
    child: Row(
      children: [
        const Icon(Icons.subdirectory_arrow_right, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                body.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xff989aa5)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cancel',
          visualDensity: VisualDensity.compact,
          onPressed: onCancel,
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
}
