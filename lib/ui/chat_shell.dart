import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'security_center.dart';
import 'rich_message.dart';
import 'matrix_html_text.dart';

class ChatShell extends StatefulWidget {
  const ChatShell({required this.backend, super.key});

  final ChatBackend backend;

  @override
  State<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends State<ChatShell> {
  final _message = QuillController.basic();
  final _composerFocus = FocusNode(debugLabel: 'message composer');
  bool _sending = false;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
  String? _mentionQuery;
  int? _mentionStart;
  int _mentionSelectionIndex = 0;

  @override
  void initState() {
    super.initState();
    _message.addListener(_updateMentionQuery);
  }

  void _updateMentionQuery() {
    final text = _message.document.toPlainText();
    final cursor = _message.selection.extentOffset.clamp(0, text.length);
    final beforeCursor = text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(beforeCursor);
    final query = match?.group(1);
    final start = match == null ? null : beforeCursor.lastIndexOf('@');
    if (query == _mentionQuery && start == _mentionStart) return;
    setState(() {
      _mentionQuery = query;
      _mentionStart = start;
      _mentionSelectionIndex = 0;
    });
  }

  void _insertMention(String userId) {
    final start = _mentionStart;
    if (start == null) return;
    final end = _message.selection.extentOffset;
    _message.replaceText(
      start,
      end - start,
      '$userId ',
      TextSelection.collapsed(offset: start + userId.length + 1),
    );
    _message.formatText(
      start,
      userId.length,
      LinkAttribute('https://matrix.to/#/$userId'),
    );
    setState(() {
      _mentionQuery = null;
      _mentionStart = null;
    });
    _composerFocus.requestFocus();
  }

  Future<void> _send() async {
    final serialized = serializeRichMessage(_message.document);
    final text = serialized.plainText.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _message.clear();
    try {
      await widget.backend.sendMessage(
        text,
        formattedBody: serialized.html,
        replyToMessageId: _replyingTo?.id,
        editMessageId: _editingMessage?.id,
      );
      if (mounted) {
        _message.clear();
        setState(() {
          _replyingTo = null;
          _editingMessage = null;
        });
      }
    } catch (_) {
      // Leave the document intact so a failed send can be retried.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _replyTo(ChatMessage message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  void _edit(ChatMessage message) {
    _message.document = Document()..insert(0, message.body);
    _message.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: message.body.length),
      ChangeSource.local,
    );
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
    });
    _composerFocus.requestFocus();
  }

  void _cancelComposerAction() {
    setState(() {
      _replyingTo = null;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  Future<void> _attachFile() async {
    if (_sending) return;
    final result = await FilePicker.pickFiles(withData: true);
    if (!mounted || result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes ?? await result.xFiles.single.readAsBytes();
    if (!mounted) return;
    var spoiler = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Send attachment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(picked.name, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: spoiler,
                onChanged: (value) =>
                    setDialogState(() => spoiler = value ?? false),
                title: const Text('Mark as spoiler'),
                subtitle: const Text('Hidden until the recipient reveals it.'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sending = true);
    try {
      await widget.backend.sendAttachment(
        AttachmentDraft(
          bytes: bytes,
          name: picked.name,
          mimeType:
              lookupMimeType(picked.name, headerBytes: bytes) ??
              'application/octet-stream',
          spoiler: spoiler,
        ),
        replyToMessageId: _replyingTo?.id,
      );
      if (mounted) setState(() => _replyingTo = null);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _message.removeListener(_updateMentionQuery);
    _message.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (widget.backend.encryptionSetup.needsAttention)
            _SecurityBanner(backend: widget.backend),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 68, child: _SpaceBar(backend: widget.backend)),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 280,
                  child: _RoomPanel(backend: widget.backend),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: widget.backend.selectedRoom == null
                      ? const _EmptyConversation()
                      : _Conversation(
                          backend: widget.backend,
                          controller: _message,
                          composerFocus: _composerFocus,
                          sending: _sending,
                          replyingTo: _replyingTo,
                          editingMessage: _editingMessage,
                          onSend: _send,
                          onReply: _replyTo,
                          onEdit: _edit,
                          onCancelComposerAction: _cancelComposerAction,
                          onAttach: _attachFile,
                          mentionSuggestions: _mentionSuggestions,
                          mentionSelectionIndex: _mentionSelectionIndex,
                          onMentionSelected: _insertMention,
                          onMentionSelectionChanged: (index) =>
                              setState(() => _mentionSelectionIndex = index),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<MentionSuggestion> get _mentionSuggestions {
    final query = _mentionQuery?.toLowerCase();
    if (query == null) return const [];
    return widget.backend.mentionSuggestions
        .where(
          (suggestion) =>
              suggestion.displayName.toLowerCase().contains(query) ||
              suggestion.userId.toLowerCase().contains(query),
        )
        .take(6)
        .toList(growable: false);
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff4b3c19),
    child: InkWell(
      onTap: () => showSecurityCenter(context, backend),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 19),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Encrypted history is not fully protected on this device.',
              ),
            ),
            TextButton(
              onPressed: () => showSecurityCenter(context, backend),
              child: const Text('Fix encryption'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SpaceBar extends StatelessWidget {
  const _SpaceBar({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff191a1e),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        children: [
          _SpaceButton(
            tooltip: 'Home',
            selected: backend.selectedSpaceId == null,
            onTap: () => backend.selectSpace(null),
            child: const Icon(Icons.home_filled, size: 21),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Divider(height: 1),
          ),
          for (final space in backend.spaces)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _SpaceButton(
                tooltip: space.name,
                selected: backend.selectedSpaceId == space.id,
                onTap: () => backend.selectSpace(space.id),
                child: space.avatarBytes == null
                    ? Text(
                        _initials(space.name),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Image.memory(
                        space.avatarBytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }
}

class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 48,
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : const Color(0xff2b2d34),
          borderRadius: BorderRadius.circular(selected ? 13 : 24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(selected ? 13 : 24),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _RoomPanel extends StatelessWidget {
  const _RoomPanel({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff202126),
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xff35363d))),
            ),
            child: Text(
              backend.selectedSpaceId == null
                  ? 'Home'
                  : backend.spaces
                            .where(
                              (space) => space.id == backend.selectedSpaceId,
                            )
                            .map((space) => space.name)
                            .firstOrNull ??
                        'Space',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: backend.rooms.isEmpty
                ? const Center(child: Text('No joined rooms'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: backend.rooms.length,
                    itemBuilder: (context, index) {
                      final room = backend.rooms[index];
                      final selected = backend.selectedRoom?.id == room.id;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        leading: _RoomIcon(room: room, size: 30),
                        title: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          room.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: room.unreadCount > 0
                            ? Badge(label: Text('${room.unreadCount}'))
                            : null,
                        onTap: () => backend.selectRoom(room.id),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: Text(
              backend.userId ?? 'Matrix account',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Encryption & recovery',
              icon: Icon(
                backend.encryptionSetup.status == EncryptionSetupStatus.ready
                    ? Icons.verified_user
                    : Icons.gpp_maybe,
                size: 19,
              ),
              onPressed: () => showSecurityCenter(context, backend),
            ),
          ),
          SizedBox(
            height: 34,
            child: TextButton.icon(
              onPressed: backend.logout,
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Log out'),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({required this.room, required this.size});

  final RoomSummary room;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (room.usesChannelIcon) {
      return SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.tag, size: 18),
      );
    }
    final avatar = room.avatarBytes;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xff3a3c46),
      backgroundImage: avatar == null ? null : MemoryImage(avatar),
      child: avatar == null
          ? Text(
              room.name.trim().isEmpty
                  ? '?'
                  : room.name.trim().characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.backend,
    required this.controller,
    required this.composerFocus,
    required this.sending,
    required this.replyingTo,
    required this.editingMessage,
    required this.onSend,
    required this.onReply,
    required this.onEdit,
    required this.onCancelComposerAction,
    required this.onAttach,
    required this.mentionSuggestions,
    required this.mentionSelectionIndex,
    required this.onMentionSelected,
    required this.onMentionSelectionChanged,
  });

  final ChatBackend backend;
  final QuillController controller;
  final FocusNode composerFocus;
  final bool sending;
  final ChatMessage? replyingTo;
  final ChatMessage? editingMessage;
  final VoidCallback onSend;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onEdit;
  final VoidCallback onCancelComposerAction;
  final VoidCallback onAttach;
  final List<MentionSuggestion> mentionSuggestions;
  final int mentionSelectionIndex;
  final ValueChanged<String> onMentionSelected;
  final ValueChanged<int> onMentionSelectionChanged;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  String? _roomId;

  @override
  void initState() {
    super.initState();
    _roomId = widget.backend.selectedRoom?.id;
    _scrollController.addListener(_loadHistoryNearTop);
    _focusComposerAfterBuild();
  }

  void _focusComposerAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.sending) widget.composerFocus.requestFocus();
    });
  }

  void _loadHistoryNearTop() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      widget.backend.loadMoreHistory();
    }
  }

  void _jumpToFirstUnread() {
    final eventId = widget.backend.firstUnreadMessageId;
    if (eventId == null || !_scrollController.hasClients) return;
    final index = widget.backend.messages.indexWhere(
      (message) => message.id == eventId,
    );
    if (index < 0) return;
    final estimated = (index * 64.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(estimated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _messageKeys[eventId]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 180),
          alignment: 0.5,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant _Conversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roomId = widget.backend.selectedRoom?.id;
    if (_roomId != roomId) {
      _roomId = roomId;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _focusComposerAfterBuild();
    } else if (oldWidget.sending && !widget.sending) {
      _focusComposerAfterBuild();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This removes the message for everyone in the room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.backend.redactMessage(message.id);
  }

  Future<void> _pickReaction(ChatMessage message) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final emoji = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(origin.dx + 360, origin.dy + 120, 0, 0),
      items: const ['👍', '❤️', '😂', '🎉', '👀', '❓']
          .map(
            (emoji) => PopupMenuItem(
              value: emoji,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          )
          .toList(growable: false),
    );
    if (emoji != null) await widget.backend.toggleReaction(message.id, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final room = backend.selectedRoom!;
    final messages = backend.messages;
    return Column(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            color: Color(0xff292a30),
            border: Border(bottom: BorderSide(color: Color(0xff35363d))),
          ),
          child: Row(
            children: [
              _RoomIcon(room: room, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  room.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (backend.firstUnreadMessageId != null)
                IconButton(
                  tooltip: 'Jump to first unread',
                  onPressed: _jumpToFirstUnread,
                  icon: const Icon(Icons.mark_chat_unread_outlined, size: 19),
                ),
              IconButton(
                tooltip: backend.selectedRoomMuted
                    ? 'Unmute room notifications'
                    : 'Mute room notifications',
                onPressed: () =>
                    backend.setSelectedRoomMuted(!backend.selectedRoomMuted),
                icon: Icon(
                  backend.selectedRoomMuted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_none,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
        if (backend.error case final error?)
          MaterialBanner(
            content: Text(error),
            actions: [
              TextButton(
                onPressed: backend.clearError,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Expanded(
          child: backend.timelineLoading
              ? const Center(child: CircularProgressIndicator())
              : backend.messages.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
                  itemCount:
                      messages.length +
                      (backend.historyLoading || backend.canLoadMoreHistory
                          ? 1
                          : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: backend.historyLoading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton.icon(
                                  onPressed: backend.loadMoreHistory,
                                  icon: const Icon(Icons.history, size: 17),
                                  label: const Text('Load older messages'),
                                ),
                        ),
                      );
                    }
                    final message = messages[index];
                    final older = index + 1 < messages.length
                        ? messages[index + 1]
                        : null;
                    final startsGroup =
                        older == null ||
                        older.sender != message.sender ||
                        message.timestamp.difference(older.timestamp) >
                            const Duration(minutes: 7) ||
                        message.reply != null;
                    return Column(
                      key: _messageKeys.putIfAbsent(message.id, GlobalKey.new),
                      children: [
                        if (message.id == backend.firstUnreadMessageId)
                          const _UnreadDivider(),
                        _MessageRow(
                          message: message,
                          startsGroup: startsGroup,
                          onReply: () => widget.onReply(message),
                          onEdit: message.own && !message.redacted
                              ? () => widget.onEdit(message)
                              : null,
                          onDelete: message.canRedact
                              ? () => _deleteMessage(message)
                              : null,
                          onReact: message.redacted || message.system
                              ? null
                              : () => _pickReaction(message),
                          onRetry: message.failed
                              ? () => backend.retryMessage(message.id)
                              : null,
                          onCancel: message.pending || message.failed
                              ? () => backend.cancelPendingMessage(message.id)
                              : null,
                          onToggleReaction: (key) =>
                              backend.toggleReaction(message.id, key),
                          backend: backend,
                        ),
                      ],
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        if (widget.replyingTo case final message?)
          _ComposerContext(
            label: 'Replying to ${message.sender}',
            body: message.body,
            onCancel: widget.onCancelComposerAction,
          )
        else if (widget.editingMessage case final message?)
          _ComposerContext(
            label: 'Editing message',
            body: message.body,
            onCancel: widget.onCancelComposerAction,
          ),
        if (widget.mentionSuggestions.isNotEmpty)
          _MentionPicker(
            suggestions: widget.mentionSuggestions,
            selectedIndex: widget.mentionSelectionIndex,
            onSelected: widget.onMentionSelected,
          ),
        _RichComposer(
          controller: widget.controller,
          focusNode: widget.composerFocus,
          roomName: room.name,
          enabled: !widget.sending,
          onSend: widget.onSend,
          onAttach: widget.onAttach,
          mentionSuggestions: widget.mentionSuggestions,
          mentionSelectionIndex: widget.mentionSelectionIndex,
          onMentionSelected: widget.onMentionSelected,
          onMentionSelectionChanged: widget.onMentionSelectionChanged,
        ),
      ],
    );
  }
}

class _RichComposer extends StatefulWidget {
  const _RichComposer({
    required this.controller,
    required this.focusNode,
    required this.roomName,
    required this.enabled,
    required this.onSend,
    required this.onAttach,
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
              subtitle: Text(suggestion.userId),
              onTap: () => onSelected(suggestion.userId),
            );
          },
        ),
      ),
    ),
  );
}

class _RichComposerState extends State<_RichComposer> {
  final _scrollController = ScrollController();

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
        IconButton(
          tooltip: 'Add media or file',
          visualDensity: VisualDensity.compact,
          onPressed: widget.enabled ? widget.onAttach : null,
          icon: const Icon(Icons.add_circle_outline, size: 25),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xff777985)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: QuillEditor(
              controller: widget.controller,
              focusNode: widget.focusNode,
              scrollController: _scrollController,
              config: QuillEditorConfig(
                autoFocus: false,
                minHeight: 32,
                maxHeight: 132,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                placeholder: 'Message #${widget.roomName}',
                // ignore: experimental_member_use
                onKeyPressed: (event, _) {
                  if (event is KeyDownEvent &&
                      widget.mentionSuggestions.isNotEmpty) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
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
                            .mentionSuggestions[widget.mentionSelectionIndex]
                            .userId,
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
        ),
        IconButton(
          tooltip: 'Send',
          visualDensity: VisualDensity.compact,
          onPressed: widget.enabled ? widget.onSend : null,
          icon: const Icon(Icons.send, size: 25),
        ),
      ],
    ),
  );
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    required this.message,
    required this.startsGroup,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onRetry,
    required this.onCancel,
    required this.onToggleReaction,
    required this.backend,
  });

  final ChatMessage message;
  final bool startsGroup;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final ValueChanged<String> onToggleReaction;
  final ChatBackend backend;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  Timer? _hoverTimer;
  bool _hovered = false;
  bool _showActions = false;

  ChatMessage get message => widget.message;

  void _enter(PointerEnterEvent _) {
    _hoverTimer?.cancel();
    setState(() => _hovered = true);
    _hoverTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _hovered) setState(() => _showActions = true);
    });
  }

  void _exit(PointerExitEvent _) {
    _hoverTimer?.cancel();
    setState(() => _hovered = false);
    _hoverTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_hovered) setState(() => _showActions = false);
    });
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final local = message.timestamp.toLocal();
    final now = DateTime.now();
    final clock = TimeOfDay.fromDateTime(local).format(context);
    final time =
        local.year == now.year &&
            local.month == now.month &&
            local.day == now.day
        ? clock
        : '${local.day}/${local.month}/${local.year} $clock';
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
        child: Text(
          message.body,
          style: const TextStyle(
            color: Color(0xff989aa5),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return MouseRegion(
      onEnter: _enter,
      onExit: _exit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        color: _hovered ? const Color(0xff292a30) : Colors.transparent,
        child: Opacity(
          opacity: message.pending ? 0.55 : 1,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, widget.startsGroup ? 8 : 1, 20, 1),
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.startsGroup)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: const Color(0xff3a3c46),
                          backgroundImage: message.avatarBytes == null
                              ? null
                              : MemoryImage(message.avatarBytes!),
                          child: message.avatarBytes == null
                              ? Text(
                                  message.sender.trim().isEmpty
                                      ? '?'
                                      : message.sender.characters.first
                                            .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                      )
                    else
                      const SizedBox(width: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.startsGroup)
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    message.sender,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      height: 1.05,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  time,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: const Color(0xff989aa5),
                                      ),
                                ),
                              ],
                            ),
                          if (message.reply case final reply?)
                            Container(
                              margin: const EdgeInsets.only(top: 3, bottom: 2),
                              padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
                              decoration: const BoxDecoration(
                                color: Color(0xff292a30),
                                border: Border(
                                  left: BorderSide(
                                    color: Color(0xff747fdb),
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reply.sender,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xffb8bfff),
                                    ),
                                  ),
                                  Text(
                                    reply.body.replaceAll('\n', ' '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          if (message.body.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.zero,
                              child: message.formattedBody != null
                                  ? MatrixHtmlText(
                                      html: message.formattedBody!,
                                      fallback: message.body,
                                    )
                                  : SelectableText(
                                      message.body,
                                      style: TextStyle(
                                        height: 1.16,
                                        fontStyle: message.redacted
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                        color: message.redacted
                                            ? const Color(0xff989aa5)
                                            : null,
                                      ),
                                    ),
                            ),
                          if (message.attachment case final attachment?)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: _AttachmentView(
                                backend: widget.backend,
                                messageId: message.id,
                                attachment: attachment,
                              ),
                            ),
                          if (message.edited)
                            const Text(
                              '(edited)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xff989aa5),
                              ),
                            ),
                          if (message.failed)
                            Row(
                              children: [
                                const Text(
                                  'Failed to send',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.redAccent,
                                  ),
                                ),
                                TextButton(
                                  onPressed: widget.onRetry,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          if (message.transferStatus case final status?)
                            Text(
                              status,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xffb8bfff),
                              ),
                            ),
                          if (message.reactions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final reaction in message.reactions)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: reaction.reactedByMe
                                          ? const Color(0xff424a78)
                                          : const Color(0xff303139),
                                      label: Text(
                                        '${reaction.key} ${reaction.count}',
                                      ),
                                      onPressed: () =>
                                          widget.onToggleReaction(reaction.key),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_showActions)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xff202126),
                        border: Border.all(color: const Color(0xff41434c)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _MessageActions(
                        onReply: widget.onReply,
                        onEdit: widget.onEdit,
                        onDelete: widget.onDelete,
                        onReact: widget.onReact,
                        onRetry: widget.onRetry,
                        onCancel: widget.onCancel,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Divider(color: Color(0xffff6f77), thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 9),
          child: Text(
            'NEW',
            style: TextStyle(
              color: Color(0xffff8b91),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xffff6f77), thickness: 1)),
      ],
    ),
  );
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onRetry,
    required this.onCancel,
  });

  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: 'Reply',
        onPressed: onReply,
        icon: const Icon(Icons.reply, size: 16),
      ),
      PopupMenuButton<String>(
        tooltip: 'Message actions',
        iconSize: 17,
        onSelected: (action) => switch (action) {
          'react' => onReact?.call(),
          'edit' => onEdit?.call(),
          'delete' => onDelete?.call(),
          'retry' => onRetry?.call(),
          'cancel' => onCancel?.call(),
          _ => null,
        },
        itemBuilder: (context) => [
          if (onReact != null)
            const PopupMenuItem(value: 'react', child: Text('Add reaction')),
          if (onEdit != null)
            const PopupMenuItem(value: 'edit', child: Text('Edit message')),
          if (onDelete != null)
            const PopupMenuItem(value: 'delete', child: Text('Delete message')),
          if (onRetry != null)
            const PopupMenuItem(value: 'retry', child: Text('Retry send')),
          if (onCancel != null)
            const PopupMenuItem(
              value: 'cancel',
              child: Text('Remove failed send'),
            ),
        ],
      ),
    ],
  );
}

class _AttachmentView extends StatefulWidget {
  const _AttachmentView({
    required this.backend,
    required this.messageId,
    required this.attachment,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  Future<Uint8List>? _imageBytes;
  bool _revealed = false;
  bool _saving = false;
  bool _opening = false;

  Future<void> _save() async {
    if (_saving) return;
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save attachment',
      fileName: widget.attachment.name,
    );
    if (path == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final bytes = await widget.backend.downloadAttachment(widget.messageId);
      await File(path).writeAsBytes(bytes, flush: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final bytes = await widget.backend.downloadAttachment(widget.messageId);
      final directory = await getTemporaryDirectory();
      final name = path.basename(widget.attachment.name);
      final file = File(
        path.join(
          directory.path,
          '${widget.messageId.hashCode}_${name.isEmpty ? 'attachment' : name}',
        ),
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!await launchUrl(Uri.file(file.path))) {
        throw StateError('No application is available to open this file.');
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open attachment: $exception')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attachment.spoiler && !_revealed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 208,
          height: 116,
          child: Material(
            color: const Color(0xff17181c),
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              onTap: () => setState(() => _revealed = true),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off_outlined, size: 17),
                    SizedBox(height: 2),
                    Text('Reveal spoiler', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return switch (widget.attachment.kind) {
      AttachmentKind.image => _buildImage(),
      AttachmentKind.video => _InlineVideo(
        backend: widget.backend,
        messageId: widget.messageId,
        attachment: widget.attachment,
        onSave: _save,
        onOpen: _open,
      ),
      AttachmentKind.audio => _InlineAudio(
        backend: widget.backend,
        messageId: widget.messageId,
        attachment: widget.attachment,
        onSave: _save,
        onOpen: _open,
      ),
      AttachmentKind.file => _buildFile(),
    };
  }

  Widget _buildImage() {
    _imageBytes ??= widget.backend.downloadAttachment(
      widget.messageId,
      thumbnail: !widget.attachment.animated,
    );
    return FutureBuilder<Uint8List>(
      future: _imageBytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FileTile(
            attachment: widget.attachment,
            saving: _saving,
            onSave: _save,
            opening: _opening,
            onOpen: _open,
            error: 'Preview unavailable',
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const SizedBox(
            width: 184,
            height: 144,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 184, maxHeight: 144),
            child: InkWell(
              onTap: _open,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFile() => _FileTile(
    attachment: widget.attachment,
    saving: _saving,
    onSave: _save,
    opening: _opening,
    onOpen: _open,
  );
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.attachment,
    required this.saving,
    required this.onSave,
    required this.opening,
    required this.onOpen,
    this.error,
  });

  final ChatAttachment attachment;
  final bool saving;
  final VoidCallback onSave;
  final bool opening;
  final VoidCallback onOpen;
  final String? error;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 460),
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
    decoration: BoxDecoration(
      color: const Color(0xff292a30),
      border: Border.all(color: const Color(0xff3b3d45)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [
        Icon(
          attachment.kind == AttachmentKind.audio
              ? Icons.audio_file_outlined
              : Icons.insert_drive_file_outlined,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attachment.name, overflow: TextOverflow.ellipsis),
              Text(
                error ?? _fileDetails(attachment),
                style: const TextStyle(fontSize: 11, color: Color(0xff989aa5)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Open attachment',
          onPressed: opening ? null : onOpen,
          icon: opening
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_new, size: 18),
        ),
        IconButton(
          tooltip: 'Save attachment',
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download, size: 19),
        ),
      ],
    ),
  );

  String _fileDetails(ChatAttachment attachment) {
    final size = attachment.size;
    if (size == null) return attachment.mimeType;
    final amount = size >= 1024 * 1024
        ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(size / 1024).toStringAsFixed(0)} KB';
    return '${attachment.mimeType} · $amount';
  }
}

class _InlineVideo extends StatefulWidget {
  const _InlineVideo({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.onSave,
    required this.onOpen,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final VoidCallback onSave;
  final VoidCallback onOpen;

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  bool _opening = false;
  bool _opened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (_opening || _opened) return;
    setState(() => _opening = true);
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) return;
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: false,
      );
      _opened = true;
    } catch (exception) {
      _error = exception.toString();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _play() async {
    if (_opening) return;
    if (_opened) {
      await _player.playOrPause();
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) {
        throw StateError('Encrypted streaming is still being prepared.');
      }
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: true,
      );
      _opened = true;
    } catch (exception) {
      if (mounted) setState(() => _error = exception.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      width: 208,
      height: 118,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Video(controller: _controller),
            if (!_player.state.playing)
              IconButton.filled(
                tooltip: 'Stream video',
                onPressed: _opening ? null : _play,
                icon: _opening
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
              ),
            Positioned(
              right: 0,
              top: 0,
              child: SizedBox.square(
                dimension: 24,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  tooltip: 'Video options',
                  onSelected: (value) =>
                      value == 'open' ? widget.onOpen() : widget.onSave(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'open',
                      child: Text('Open externally'),
                    ),
                    PopupMenuItem(value: 'save', child: Text('Save video')),
                  ],
                ),
              ),
            ),
            if (_error case final error?)
              Positioned(
                left: 3,
                right: 3,
                bottom: 2,
                child: Text(
                  error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _InlineAudio extends StatefulWidget {
  const _InlineAudio({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.onSave,
    required this.onOpen,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final VoidCallback onSave;
  final VoidCallback onOpen;

  @override
  State<_InlineAudio> createState() => _InlineAudioState();
}

class _InlineAudioState extends State<_InlineAudio> {
  late final Player _player = Player();
  bool _opening = false;
  bool _opened = false;
  String? _error;

  Future<void> _toggle() async {
    if (_opening) return;
    if (_opened) {
      await _player.playOrPause();
      return;
    }
    setState(() => _opening = true);
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) throw StateError('Audio playback is unavailable.');
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: true,
      );
      _opened = true;
    } catch (exception) {
      _error = exception.toString();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 460),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xff292a30),
      border: Border.all(color: const Color(0xff3b3d45)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _player.state.playing,
      builder: (context, snapshot) => Row(
        children: [
          IconButton(
            tooltip: snapshot.data == true ? 'Pause' : 'Play audio',
            onPressed: _toggle,
            icon: _opening
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(snapshot.data == true ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.attachment.name, overflow: TextOverflow.ellipsis),
                if (_error case final error?)
                  Text(
                    error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open audio externally',
            onPressed: widget.onOpen,
            icon: const Icon(Icons.open_in_new, size: 18),
          ),
          IconButton(
            tooltip: 'Save audio',
            onPressed: widget.onSave,
            icon: const Icon(Icons.download, size: 19),
          ),
        ],
      ),
    ),
  );
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

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forum_outlined, size: 46),
        SizedBox(height: 12),
        Text('Choose a room to start chatting'),
      ],
    ),
  );
}
