import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/chat_models.dart';

InlineSpan messageMetadata(
  BuildContext context,
  ChatMessage message, {
  required bool showReceipt,
  VoidCallback? onReaders,
  bool inHeader = false,
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
  final span = TextSpan(
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
  return inHeader || (!showReceipt && !message.edited)
      ? span
      : MessageMetadataSpan(message.id, span);
}

class MessageMetadataSpan extends TextSpan {
  MessageMetadataSpan(this.messageId, InlineSpan span)
    : super(children: [span]);
  final String messageId;
}

/// Measure the actual rendered rich text, including emoji and spoilers. Status
/// markers never consume the width used to lay out an attachment or message.
class TrailingMessageMetadata extends StatelessWidget {
  const TrailingMessageMetadata({
    super.key,
    required this.child,
    required this.metadata,
    this.ids = const [],
    this.text = true,
  });
  final Widget child;
  final InlineSpan? metadata;
  final List<String> ids;
  final bool text;
  @override
  Widget build(BuildContext context) {
    final span = metadata;
    if (span == null) return child;
    final keys = span is MessageMetadataSpan ? [span.messageId] : ids;
    if (keys.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: child),
          Text.rich(span),
        ],
      );
    }
    final scope = ReceiptPlacementScope.of(context);
    return _MeasuredMetadata(
      text: text,
      report: (overflow) => scope?.report(keys, overflow),
      children: [child, Text.rich(span, maxLines: 1, softWrap: false)],
    );
  }
}

class _MeasuredMetadata extends MultiChildRenderObjectWidget {
  const _MeasuredMetadata({
    required this.text,
    required this.report,
    required super.children,
  });
  final bool text;
  final ValueChanged<bool> report;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MetadataLayout(text, report);
  @override
  void updateRenderObject(BuildContext context, _MetadataLayout renderObject) {
    renderObject
      ..isText = text
      ..report = report
      ..markNeedsLayout();
  }
}

class _MetadataParentData extends ContainerBoxParentData<RenderBox> {}

class _MetadataLayout extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _MetadataLayout(this.isText, this.report);
  bool isText;
  ValueChanged<bool> report;
  bool _overflow = false;
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _MetadataParentData();
    }
  }

  Rect? _lastLine(RenderBox root) {
    Rect? found;
    void visit(RenderObject object) {
      List<TextBox>? boxes;
      final span = switch (object) {
        RenderParagraph p => p.text,
        RenderEditable e => e.text,
        _ => null,
      };
      if (span != null) {
        final length = span.toPlainText().length;
        if (length > 0) {
          final selection = TextSelection(
            baseOffset: length - 1,
            extentOffset: length,
          );
          boxes = switch (object) {
            RenderParagraph p => p.getBoxesForSelection(selection),
            RenderEditable e => e.getBoxesForSelection(selection),
            _ => null,
          };
        }
        if (boxes?.isNotEmpty == true) {
          found = MatrixUtils.transformRect(
            object.getTransformTo(root),
            boxes!.last.toRect(),
          );
        }
        return;
      }
      object.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  @override
  void performLayout() {
    final body = firstChild!, marker = lastChild!;
    body.layout(constraints.loosen(), parentUsesSize: true);
    marker.layout(const BoxConstraints(), parentUsesSize: true);
    final end = isText ? _lastLine(body) : null;
    final x = (end?.right ?? body.size.width) + 3;
    final bottom = end?.bottom ?? body.size.height;
    _overflow = x + marker.size.width > constraints.maxWidth;
    (body.parentData as ContainerBoxParentData).offset = Offset.zero;
    (marker.parentData as ContainerBoxParentData).offset = Offset(
      x,
      (bottom - marker.size.height).clamp(0.0, double.infinity),
    );
    size = constraints.constrain(
      Size(
        _overflow
            ? body.size.width
            : (x + marker.size.width).clamp(body.size.width, double.infinity),
        _overflow
            ? body.size.height
            : body.size.height.clamp(marker.size.height, double.infinity),
      ),
    );
    final overflow = _overflow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) report(overflow);
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(firstChild!, offset);
    if (!_overflow) {
      context.paintChild(
        lastChild!,
        offset + (lastChild!.parentData as ContainerBoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_overflow) {
      final child = lastChild!,
          offset = (lastChild!.parentData as ContainerBoxParentData).offset;
      if (result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, position) =>
            child.hitTest(result, position: position),
      )) {
        return true;
      }
    }
    return firstChild!.hitTest(result, position: position);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor(firstChild!);
    if (!_overflow) visitor(lastChild!);
  }
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
              .where((item) => (receiptIds.contains(item.id) || item.edited))
              .toList();
    if (entries.isEmpty) return child;
    return TrailingMessageMetadata(
      key: ValueKey('media-receipt-${message.id}'),
      text: false,
      ids: entries.map((e) => e.id).toList(),
      metadata: TextSpan(
        children: [
          for (final item in entries)
            messageMetadata(
              context,
              item,
              showReceipt: album.isEmpty
                  ? showReceipt
                  : receiptIds.contains(item.id),
            ),
        ],
      ),
      child: child,
    );
  }
}

/// Compute metadata placement once per viewport width. Keep receipt ownership
/// attached to its original event even when its visual marker moves to a header.
class ReceiptPlacement extends StatefulWidget {
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
  State<ReceiptPlacement> createState() => _ReceiptPlacementState();
}

class _ReceiptPlacementState extends State<ReceiptPlacement> {
  final _overflow = <String>{};
  void _report(List<String> ids, bool overflow) {
    if (!mounted || ids.every((id) => _overflow.contains(id) == overflow)) {
      return;
    }
    setState(() {
      for (final id in ids) {
        if (overflow) {
          _overflow.add(id);
        } else {
          _overflow.remove(id);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ReceiptPlacement oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.messages.map((m) => m.id).toSet();
    _overflow.removeWhere((id) => !ids.contains(id));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final messages = widget.messages,
          receiptIds = widget.receiptIds,
          hiddenIds = widget.hiddenIds;
      final headers = <String, List<ChatMessage>>{};
      final relocated = <String>{};
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        if (!receiptIds.contains(message.id) && !message.edited) continue;
        if (!_overflow.contains(message.id)) continue;
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
        report: _report,
        child: widget.child,
      );
    },
  );
}

class ReceiptPlacementScope extends InheritedWidget {
  const ReceiptPlacementScope({
    required this.headers,
    required this.relocated,
    required this.receiptIds,
    required this.report,
    required super.child,
    super.key,
  });
  final Map<String, List<ChatMessage>> headers;
  final Set<String> relocated, receiptIds;
  final void Function(List<String>, bool) report;
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
