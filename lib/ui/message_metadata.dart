import 'package:flutter/material.dart';
import '../models/chat_models.dart';

InlineSpan messageMetadata(
  BuildContext context,
  ChatMessage message, {
  required bool showReceipt,
  VoidCallback? onReaders,
}) {
  final color = Theme.of(context).colorScheme.onSurfaceVariant;
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
                size: 12,
                color: color,
              ),
            ),
          ),
        ),
      );
  return TextSpan(
    style: TextStyle(fontSize: 11, color: color, fontStyle: FontStyle.normal),
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
