import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class AvatarMeasureAnchor extends SingleChildRenderObjectWidget {
  const AvatarMeasureAnchor({required super.child, super.key});
  @override
  RenderObject createRenderObject(BuildContext context) => _AvatarMeasureBox();
}

class _AvatarMeasureBox extends RenderProxyBox {
  Size measuredSize = Size.zero;
  @override
  void performLayout() {
    super.performLayout();
    // A detached value, not another render object's protected layout size.
    measuredSize = Size(size.width, size.height);
  }
}

/// Keeps the desktop overlay avatar centred on its rendered header and short
/// message body. Longer messages retain their first-line alignment.
class MeasuredAvatarStack extends MultiChildRenderObjectWidget {
  const MeasuredAvatarStack({
    required this.senderKey,
    required this.bodyKey,
    required this.enabled,
    required super.children,
    super.key,
  });
  final GlobalKey senderKey, bodyKey;
  final bool enabled;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _AvatarStack(senderKey, bodyKey, enabled, Directionality.of(context));
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final stack = renderObject as _AvatarStack;
    stack
      ..senderKey = senderKey
      ..bodyKey = bodyKey
      ..enabled = enabled
      ..textDirection = Directionality.of(context)
      ..markNeedsLayout();
  }
}

class _AvatarStack extends RenderStack {
  _AvatarStack(
    this.senderKey,
    this.bodyKey,
    this.enabled,
    TextDirection direction,
  ) : super(textDirection: direction, clipBehavior: Clip.none);
  GlobalKey senderKey, bodyKey;
  bool enabled;

  bool _singleLine(_AvatarMeasureBox body) {
    RenderBox? text;
    void visit(RenderObject object) {
      if (text != null) return;
      if (object is RenderEditable || object is RenderParagraph) {
        text = object as RenderBox;
      } else {
        object.visitChildren(visit);
      }
    }

    visit(body);
    final box = text;
    if (box == null) return false;
    final source = switch (box) {
      RenderEditable editable => editable.text?.toPlainText(),
      RenderParagraph paragraph => paragraph.text.toPlainText(),
      _ => null,
    };
    if (source == null || source.isEmpty || source.contains('\n')) return false;
    final selection = TextSelection(baseOffset: 0, extentOffset: source.length);
    final boxes = switch (box) {
      RenderEditable editable => editable.getBoxesForSelection(selection),
      RenderParagraph paragraph => paragraph.getBoxesForSelection(selection),
      _ => null,
    };
    final rects = boxes
        ?.map((box) => box.toRect())
        .where((rect) => rect.height > .1)
        .toList();
    if (rects == null || rects.isEmpty) return false;
    var top = rects.first.top, bottom = rects.first.bottom;
    var bounds = rects.first;
    for (final rect in rects.skip(1)) {
      if (rect.top > top) top = rect.top;
      if (rect.bottom < bottom) bottom = rect.bottom;
      bounds = bounds.expandToInclude(rect);
    }
    // Runs of different font sizes can share a line. They must overlap
    // vertically, and there must not be another block below this paragraph.
    return bottom - top > .1 &&
        body.measuredSize.height <= bounds.height * 1.8 + 2;
  }

  @override
  void performLayout() {
    super.performLayout();
    if (!enabled || childCount < 2) return;
    final sender = senderKey.currentContext?.findRenderObject();
    final body = bodyKey.currentContext?.findRenderObject();
    if (sender is! _AvatarMeasureBox ||
        body is! _AvatarMeasureBox ||
        !sender.hasSize ||
        !body.hasSize ||
        !_singleLine(body)) {
      return;
    }
    final top = sender.localToGlobal(Offset.zero, ancestor: this).dy;
    final bottom = body
        .localToGlobal(Offset(0, body.measuredSize.height), ancestor: this)
        .dy;
    final avatar = lastChild!;
    final data = avatar.parentData! as StackParentData;
    data.offset = Offset(
      data.offset.dx,
      (top + bottom - avatar.size.height) / 2,
    );
  }
}
