import 'package:flutter/material.dart';
import '../models/chat_models.dart';

InlineSpan messageMetadata(
  BuildContext context,
  ChatMessage message, {
  required bool showReceipt,
  VoidCallback? onReaders,
}) {
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
    final entries = album.isEmpty
        ? [if (showReceipt || message.edited) message]
        : album
              .where((item) => receiptIds.contains(item.id) || item.edited)
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
