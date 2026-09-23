import 'dart:math';

import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'space_settings_screen.dart';

Future<void> showSavedMessages(
  BuildContext context,
  ChatBackend backend, {
  Future<void> Function(String roomId, String eventId)? onOpen,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: SizedBox(
      width: 620,
      height: 600,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Saved'),
                Tab(text: 'Scheduled'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _MessageList(
                    emptyLabel: 'No saved messages yet.',
                    messages: backend.bookmarkedMessages,
                    onOpen: onOpen == null
                        ? null
                        : (message) async {
                            final roomId = backend.roomIdForMessage(message.id);
                            if (roomId == null) return;
                            Navigator.pop(context);
                            await onOpen(roomId, message.id);
                          },
                  ),
                  ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (backend.scheduledMessages.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No scheduled messages.')),
                        ),
                      for (final message in backend.scheduledMessages)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.schedule_send_outlined),
                            title: Text(
                              message.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Sends ${message.sendAt.toLocal()} · ${message.roomId}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Cancel scheduled message',
                              onPressed: () async {
                                await backend.cancelScheduledMessage(
                                  message.id,
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> showPinnedMessages(
  BuildContext context,
  ChatBackend backend, {
  required Future<void> Function(String eventId) onOpen,
}) async {
  final messages = await backend.loadPinnedMessages();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: min(520, MediaQuery.sizeOf(sheetContext).height * 0.72),
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.push_pin_outlined),
              title: Text('Pinned messages'),
            ),
            Expanded(
              child: _MessageList(
                emptyLabel: 'No pinned messages.',
                messages: messages,
                onOpen: (message) async {
                  Navigator.pop(sheetContext);
                  await onOpen(message.id);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class InboxIcon extends StatelessWidget {
  const InboxIcon({required this.backend, super.key});
  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => Badge(
    key: const ValueKey('inbox-invite-badge'),
    isLabelVisible: backend.pendingInviteCount > 0,
    backgroundColor: Colors.red,
    child: const Icon(Icons.inbox_outlined),
  );
}

Future<void> showUnifiedInbox(
  BuildContext hostContext,
  ChatBackend backend, {
  required Future<void> Function(InboxItemSummary item) onOpen,
}) => showDialog<void>(
  context: hostContext,
  builder: (dialogContext) => ListenableBuilder(
    listenable: backend,
    builder: (context, _) {
      final items = backend.unifiedInbox;
      return Dialog(
        child: SizedBox(
          width: 680,
          height: 640,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.inbox_outlined),
                title: Text('Inbox'),
                subtitle: Text(
                  'Mentions, replies, reactions, calls, and invites',
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('You are all caught up.'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: item.avatarBytes == null
                                  ? null
                                  : MemoryImage(item.avatarBytes!),
                              child: item.avatarBytes == null
                                  ? Icon(_inboxIcon(item.kind))
                                  : null,
                            ),
                            title: Text(item.roomName),
                            subtitle: Text(
                              item.preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: item.kind == InboxItemKind.invite
                                ? _InviteActions(
                                    onAction: (value) async {
                                      if (value == 'accept') {
                                        await _acceptInboxInvite(
                                          hostContext,
                                          dialogContext,
                                          backend,
                                          item,
                                          onOpen,
                                        );
                                      } else {
                                        await backend.rejectRoomInvite(
                                          item.roomId,
                                        );
                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext);
                                        }
                                      }
                                    },
                                  )
                                : Text(_inboxLabel(item.kind)),
                            onTap: () async {
                              if (item.kind != InboxItemKind.invite) {
                                if (!dialogContext.mounted) return;
                                Navigator.pop(dialogContext);
                                await onOpen(item);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);

Future<void> _acceptInboxInvite(
  BuildContext hostContext,
  BuildContext dialogContext,
  ChatBackend backend,
  InboxItemSummary item,
  Future<void> Function(InboxItemSummary item) onOpen,
) async {
  await backend.acceptRoomInvite(item.roomId);
  if (dialogContext.mounted) Navigator.pop(dialogContext);
  if (item.isSpace) {
    if (!hostContext.mounted) return;
    await showSpacePages(
      hostContext,
      backend,
      item.roomId,
      skipWhenEmpty: true,
    );
    return;
  }
  await onOpen(item);
}

class _InviteActions extends StatefulWidget {
  const _InviteActions({required this.onAction});
  final Future<void> Function(String action) onAction;
  @override
  State<_InviteActions> createState() => _InviteActionsState();
}

class _InviteActionsState extends State<_InviteActions> {
  bool _busy = false;
  String? _error;
  Future<void> _run(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAction(action);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update invitation. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_error != null)
        Tooltip(message: _error!, child: const Icon(Icons.error_outline)),
      IconButton(
        tooltip: 'Ignore invitation',
        onPressed: _busy ? null : () => _run('ignore'),
        icon: const Icon(Icons.close),
      ),
      IconButton(
        tooltip: 'Accept invitation',
        onPressed: _busy ? null : () => _run('accept'),
        icon: const Icon(Icons.check),
      ),
    ],
  );
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.emptyLabel,
    required this.messages,
    required this.onOpen,
  });

  final String emptyLabel;
  final List<ChatMessage> messages;
  final ValueChanged<ChatMessage>? onOpen;

  @override
  Widget build(BuildContext context) => messages.isEmpty
      ? Center(child: Text(emptyLabel))
      : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return Card(
              child: ListTile(
                leading: message.avatarBytes == null
                    ? const Icon(Icons.message_outlined)
                    : CircleAvatar(
                        backgroundImage: MemoryImage(message.avatarBytes!),
                      ),
                title: Text(message.sender),
                subtitle: Text(
                  message.attachment?.name ?? message.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Theme.of(context).platform == TargetPlatform.android
                    ? null
                    : Text('${message.timestamp.toLocal()}'),
                onTap: onOpen == null ? null : () => onOpen!(message),
              ),
            );
          },
        );
}

IconData _inboxIcon(InboxItemKind kind) => switch (kind) {
  InboxItemKind.mention => Icons.alternate_email,
  InboxItemKind.reply => Icons.reply,
  InboxItemKind.reaction => Icons.add_reaction_outlined,
  InboxItemKind.missedCall => Icons.call_missed,
  InboxItemKind.invite => Icons.mail_outline,
};

String _inboxLabel(InboxItemKind kind) => switch (kind) {
  InboxItemKind.mention => 'Mention',
  InboxItemKind.reply => 'Reply',
  InboxItemKind.reaction => 'Reaction',
  InboxItemKind.missedCall => 'Missed call',
  InboxItemKind.invite => 'Invite',
};
