import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../models/chat_models.dart';

enum MessageAction {
  reply,
  react,
  copy,
  unread,
  pin,
  bookmark,
  edit,
  delete,
  link,
  thread,
  retry,
  discard,
}

List<MessageAction?> messageActionOrder(
  ChatMessage message, {
  required bool canEdit,
  required bool canPin,
  bool canReact = true,
}) {
  if (message.pending || message.failed) {
    return [
      MessageAction.copy,
      if (message.failed) MessageAction.retry,
      MessageAction.discard,
    ];
  }
  return [
    MessageAction.reply,
    if (canReact) MessageAction.react,
    null,
    MessageAction.copy,
    MessageAction.unread,
    if (canPin) MessageAction.pin,
    MessageAction.bookmark,
    if (message.own && canEdit && !message.redacted) MessageAction.edit,
    if (message.own && message.canRedact && !message.redacted)
      MessageAction.delete,
    MessageAction.link,
  ];
}

String messageActionLabel(MessageAction action, ChatMessage message) =>
    switch (action) {
      MessageAction.reply => 'Reply',
      MessageAction.react => 'React',
      MessageAction.copy => 'Copy',
      MessageAction.unread => 'Mark unread',
      MessageAction.pin => message.pinned ? 'Unpin' : 'Pin',
      MessageAction.bookmark =>
        message.bookmarked ? 'Remove bookmark' : 'Bookmark',
      MessageAction.edit => 'Edit',
      MessageAction.delete => 'Delete',
      MessageAction.link => 'Copy event link',
      MessageAction.thread =>
        message.threadReplyCount > 0 ? 'Open discussion' : 'Start discussion',
      MessageAction.retry => 'Retry send',
      MessageAction.discard => 'Discard failed send',
    };
IconData messageActionIcon(MessageAction action) => switch (action) {
  MessageAction.reply => Icons.reply,
  MessageAction.react => Icons.add_reaction_outlined,
  MessageAction.copy => Icons.copy_outlined,
  MessageAction.unread => Icons.mark_chat_unread_outlined,
  MessageAction.pin => Icons.push_pin_outlined,
  MessageAction.bookmark => Icons.bookmark_border,
  MessageAction.edit => Icons.edit_outlined,
  MessageAction.delete => Icons.delete_outline,
  MessageAction.link => Icons.link,
  MessageAction.thread => Icons.forum_outlined,
  MessageAction.retry => Icons.refresh,
  MessageAction.discard => Icons.close,
};

class MessageActionList extends StatelessWidget {
  const MessageActionList({
    required this.message,
    required this.actions,
    required this.onAction,
    this.onThread,
    super.key,
  });
  final ChatMessage message;
  final List<MessageAction?> actions;
  final ValueChanged<MessageAction> onAction;
  final VoidCallback? onThread;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in [
            for (final item in actions) ...[
              item,
              if (onThread != null &&
                  (item == MessageAction.react ||
                      (item == MessageAction.reply &&
                          !actions.contains(MessageAction.react))))
                MessageAction.thread,
            ],
          ])
            if (action == null)
              const SizedBox(height: 12)
            else
              ListTile(
                key: ValueKey('message-action-${action.name}'),
                dense: true,
                minTileHeight: 38,
                leading: Icon(
                  messageActionIcon(action),
                  size: 19,
                  color: action == MessageAction.delete
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(
                  messageActionLabel(action, message),
                  style: TextStyle(
                    color: action == MessageAction.delete
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                onTap: action == MessageAction.thread
                    ? onThread
                    : () => onAction(action),
              ),
        ],
      ),
    ),
  );
}

/// Observe taps without competing with selection, links or swipe gestures.
class TripleTapEdit extends StatefulWidget {
  const TripleTapEdit({required this.child, this.onEdit, super.key});
  final Widget child;
  final VoidCallback? onEdit;
  @override
  State<TripleTapEdit> createState() => _TripleTapEditState();
}

class _TripleTapEditState extends State<TripleTapEdit> {
  Offset? _down, _last;
  Duration? _at;
  int _count = 0;
  bool _moved = false;
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      _moved = false;
      _down = event.buttons == kPrimaryButton ? event.position : null;
    },
    onPointerMove: (event) {
      if (_down != null && (event.position - _down!).distance > kTouchSlop) {
        _moved = true;
      }
    },
    onPointerCancel: (_) {
      _down = null;
      _count = 0;
    },
    onPointerUp: (event) {
      if (widget.onEdit == null || _down == null || _moved) {
        _count = 0;
        return;
      }
      final close =
          _at != null &&
          event.timeStamp - _at! < const Duration(milliseconds: 400) &&
          _last != null &&
          (event.position - _last!).distance < kTouchSlop;
      _count = close ? _count + 1 : 1;
      _at = event.timeStamp;
      _last = event.position;
      _down = null;
      if (_count == 3) {
        _count = 0;
        widget.onEdit!();
      }
    },
    child: widget.child,
  );
}
