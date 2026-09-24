import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/chat_models.dart';

InlineSpan messageMetadata(
  BuildContext context,
  ChatMessage message, {
  required bool showReceipt,
  VoidCallback? onReaders,
  bool inHeader = false,
}) {
  if (!inHeader &&
      ReceiptPlacementScope.of(context)?.relocated.contains(message.id) ==
          true) {
    return const TextSpan();
  }
  final scheme = Theme.of(context).colorScheme;
  final color = MediaQuery.highContrastOf(context)
      ? scheme.onSurface
      : Color.lerp(scheme.onSurface, scheme.surface, 0.42)!;
  InlineSpan receipt(List<ReceiptReaderSummary> readers, String sentLabel) =>
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Tooltip(
          message: readers.isEmpty
              ? sentLabel
              : 'Read by ${readers.map((r) => r.displayName).join(', ')}',
          child: GestureDetector(
            onTap: readers.isEmpty ? null : onReaders,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                readers.isEmpty ? Icons.check : Icons.done_all,
                size: 10,
                color: color,
              ),
            ),
          ),
        ),
      );
  return TextSpan(
    style: TextStyle(fontSize: 10, color: color, fontStyle: FontStyle.normal),
    children: [
      if (showReceipt) receipt(message.readBy, 'Sent to homeserver'),
      if (message.edited) const TextSpan(text: ' (edited)'),
      if (showReceipt &&
          message.edited &&
          message.own &&
          message.editReadBy.isNotEmpty)
        receipt(message.editReadBy, 'Edit sent'),
    ],
  );
}

class MediaWithMessageMetadata extends StatelessWidget {
  const MediaWithMessageMetadata({
    required this.child,
    required this.message,
    required this.showReceipt,
    this.album = const [],
    this.receiptIds = const {},
    this.enabled = true,
    super.key,
  });
  final Widget child;
  final ChatMessage message;
  final bool showReceipt;
  final List<ChatMessage> album;
  final Set<String> receiptIds;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    if (ReceiptPlacementScope.of(context)?.relocated.contains(message.id) ==
        true) {
      return child;
    }
    final entries = album.isEmpty
        ? [if (showReceipt || message.edited) message]
        : album
              .where(
                (item) =>
                    (receiptIds.contains(item.id) || item.edited) &&
                    ReceiptPlacementScope.of(
                          context,
                        )?.relocated.contains(item.id) !=
                        true,
              )
              .toList();
    if (entries.isEmpty) return child;
    return Row(
      key: ValueKey('media-receipt-${message.id}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(child: child),
        const SizedBox(width: 3),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in entries)
              Tooltip(
                message: album.isEmpty
                    ? 'Message status'
                    : 'Attachment ${album.indexOf(item) + 1} of ${album.length}',
                child: Text.rich(
                  messageMetadata(
                    context,
                    item,
                    showReceipt: album.isEmpty
                        ? showReceipt
                        : receiptIds.contains(item.id),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Compute metadata placement once per viewport width. Keep receipt ownership
/// attached to its original event even when its visual marker moves to a header.
class ReceiptPlacement extends StatelessWidget {
  const ReceiptPlacement({
    required this.messages,
    required this.receiptIds,
    required this.contentInset,
    required this.child,
    this.hiddenIds = const {},
    super.key,
  });
  final List<ChatMessage> messages;
  final Set<String> receiptIds, hiddenIds;
  final double contentInset;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final headers = <String, List<ChatMessage>>{};
      final relocated = <String>{};
      final width = (constraints.maxWidth - contentInset).clamp(
        40.0,
        double.infinity,
      );
      final scaler = MediaQuery.textScalerOf(context);
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        if (!receiptIds.contains(message.id) && !message.edited) continue;
        final reserve = scaler.scale(message.edited ? 90 : 28);
        final attachment = message.attachment;
        var move = message.body.length > 8000;
        if (attachment != null && message.body.isEmpty) {
          final screen = MediaQuery.sizeOf(context);
          final desktop = contentInset > 64;
          final maxWidth = attachment.sticker
              ? 128.0
              : desktop
              ? math.min(420.0, screen.width * .5)
              : math.min(420.0, math.max(120.0, screen.width - 76));
          final maxHeight = attachment.sticker
              ? 128.0
              : math.min(520.0, screen.height * (desktop ? .5 : .52));
          final w = attachment.width, h = attachment.height;
          final mediaWidth = w != null && h != null && w > 0 && h > 0
              ? math.min(maxWidth, maxHeight * (w / h).clamp(.25, 4.0))
              : maxWidth;
          move = mediaWidth + reserve > width;
        } else if (!move) {
          final painter = TextPainter(
            text: TextSpan(
              text: message.body,
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14),
            ),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout(maxWidth: width);
          final lines = painter.computeLineMetrics();
          move = lines.isNotEmpty && lines.last.width + reserve > width;
          painter.dispose();
        }
        if (!move) continue;
        var anchor = i;
        // Only move within a contiguous sender group, never across another
        // sender, reply, day boundary or system event.
        while (anchor + 1 < messages.length) {
          final current = messages[anchor], older = messages[anchor + 1];
          if (current.reply != null ||
              older.system ||
              current.system ||
              older.senderId != message.senderId ||
              !DateUtils.isSameDay(
                older.timestamp.toLocal(),
                current.timestamp.toLocal(),
              ) ||
              current.timestamp.difference(older.timestamp) >
                  const Duration(minutes: 7)) {
            break;
          }
          anchor++;
        }
        if (hiddenIds.contains(messages[anchor].id)) anchor = i;
        if (hiddenIds.contains(messages[anchor].id)) {
          // Album members render through their visible lead item.
          while (anchor > 0 && hiddenIds.contains(messages[anchor].id)) {
            anchor--;
          }
        }
        headers.putIfAbsent(messages[anchor].id, () => []).add(message);
        relocated.add(message.id);
      }
      return ReceiptPlacementScope(
        headers: headers,
        relocated: relocated,
        receiptIds: receiptIds,
        child: child,
      );
    },
  );
}

class ReceiptPlacementScope extends InheritedWidget {
  const ReceiptPlacementScope({
    required this.headers,
    required this.relocated,
    required this.receiptIds,
    required super.child,
    super.key,
  });
  final Map<String, List<ChatMessage>> headers;
  final Set<String> relocated, receiptIds;
  static ReceiptPlacementScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReceiptPlacementScope>();
  @override
  bool updateShouldNotify(ReceiptPlacementScope oldWidget) => true;
}

class HeaderMessageMetadata extends StatelessWidget {
  const HeaderMessageMetadata({required this.messageId, super.key});
  final String messageId;
  static bool has(BuildContext context, String id) =>
      ReceiptPlacementScope.of(context)?.headers.containsKey(id) == true;
  @override
  Widget build(BuildContext context) {
    final scope = ReceiptPlacementScope.of(context);
    return Wrap(
      children: [
        for (final message in scope?.headers[messageId] ?? <ChatMessage>[])
          Tooltip(
            message:
                'Status of message sent ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(message.timestamp.toLocal()))}',
            child: Text.rich(
              messageMetadata(
                context,
                message,
                showReceipt: scope!.receiptIds.contains(message.id),
                inHeader: true,
              ),
            ),
          ),
      ],
    );
  }
}

class MessageDaySeparator extends StatelessWidget {
  const MessageDaySeparator({required this.date, super.key});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final day = DateUtils.dateOnly(date.toLocal()),
        today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final label = day == today
        ? 'Today'
        : day == yesterday
        ? 'Yesterday'
        : MaterialLocalizations.of(context).formatFullDate(day);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            const Expanded(child: Divider()),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
      ),
    );
  }
}
