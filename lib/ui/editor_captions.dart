import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class EditorCaption {
  EditorCaption(this.text, this.band, [this.position = const Offset(.5, .5)]);
  String text;
  bool band;
  Color textColor = Colors.white;
  Color outlineColor = Colors.black;
  Offset position;
  void rotateClockwise() => position = Offset(1 - position.dy, position.dx);
}

void paintCaptions(Canvas canvas, Size size, List<EditorCaption> captions) {
  for (final c in captions) {
    final font = size.shortestSide * .075;
    final p = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: c.text,
        style: TextStyle(
          color: c.textColor,
          fontSize: font,
          shadows: [
            if (c.outlineColor != Colors.transparent)
              Shadow(blurRadius: font * .15, color: c.outlineColor),
          ],
        ),
      ),
    )..layout(maxWidth: size.width * .94);
    final x = ((c.band ? .5 : c.position.dx) * size.width - p.width / 2).clamp(
      0.0,
      size.width - p.width,
    );
    final y = (c.position.dy * size.height - p.height / 2).clamp(
      0.0,
      (size.height - p.height).clamp(0.0, size.height),
    );
    if (c.band) {
      canvas.drawRect(
        Rect.fromLTWH(0, y - font * .12, size.width, p.height + font * .24),
        Paint()..color = Colors.black54,
      );
    }
    if (c.outlineColor != Colors.transparent) {
      final outline = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        text: TextSpan(
          text: c.text,
          style: TextStyle(
            fontSize: font,
            foreground: Paint()
              ..color = c.outlineColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = font * .09
              ..strokeJoin = StrokeJoin.round,
          ),
        ),
      )..layout(maxWidth: size.width * .94);
      outline.paint(canvas, Offset(x, y));
      outline.dispose();
    }
    p.paint(canvas, Offset(x, y));
    p.dispose();
  }
}

Future<Uint8List> captionBitmap(
  Size source,
  Rect crop,
  List<EditorCaption> captions,
) async {
  final size = Size(source.width * crop.width, source.height * crop.height);
  final scale = (1280 / size.longestSide).clamp(0.0, 1.0);
  final width = (size.width * scale).round().clamp(1, 1280),
      height = (size.height * scale).round().clamp(1, 1280);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(width / size.width, height / size.height)
    ..translate(-crop.left * source.width, -crop.top * source.height);
  paintCaptions(canvas, source, captions);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

class CaptionTools extends StatelessWidget {
  const CaptionTools(this.items, this.selected, this.changed, {super.key});
  final List<EditorCaption> items;
  final int selected;
  final ValueChanged<int> changed;
  Future<void> edit(BuildContext context, [EditorCaption? old]) async {
    var text = old?.text ?? '', band = old?.band ?? true;
    var ink = old?.textColor ?? Colors.white;
    var outline = old?.outlineColor ?? Colors.black;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: Text(old == null ? 'Add text' : 'Edit text'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Caption bar')),
                  ButtonSegment(value: false, label: Text('Free text')),
                ],
                selected: {band},
                onSelectionChanged: (v) => update(() => band = v.single),
              ),
              TextFormField(
                initialValue: text,
                autofocus: true,
                maxLength: 160,
                maxLines: 2,
                onChanged: (v) => update(() => text = v),
                decoration: const InputDecoration(hintText: 'Your text'),
              ),
              _CaptionPalette(
                'Text colour',
                ink,
                (value) => update(() => ink = value),
              ),
              _CaptionPalette(
                'Outline colour',
                outline,
                (value) => update(() => outline = value),
                allowNone: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !context.mounted) return;
    final item = old ?? EditorCaption('', band);
    item.text = text.trim();
    item.band = band;
    item.textColor = ink;
    item.outlineColor = outline;
    if (old == null) items.add(item);
    changed(items.indexOf(item));
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    children: [
      for (var i = 0; i < items.length; i++)
        InputChip(
          label: Text(
            items[i].text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          selected: i == selected,
          onPressed: () => changed(i),
          onDeleted: () {
            items.removeAt(i);
            changed(items.length - 1);
          },
        ),
      if (items.length < 12)
        TextButton.icon(
          onPressed: () => edit(context),
          icon: const Icon(Icons.add),
          label: const Text('Add text'),
        ),
      if (selected >= 0 && selected < items.length)
        TextButton(
          onPressed: () => edit(context, items[selected]),
          child: const Text('Edit text'),
        ),
      if (items.isNotEmpty)
        const Text('Tap or drag on the picture to place the selected text.'),
    ],
  );
}

class _CaptionPalette extends StatelessWidget {
  const _CaptionPalette(
    this.title,
    this.selected,
    this.onSelect, {
    this.allowNone = false,
  });
  final String title;
  final Color selected;
  final ValueChanged<Color> onSelect;
  final bool allowNone;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      Wrap(
        spacing: 2,
        children: [
          for (final (label, color) in [
            ('White', Colors.white),
            ('Black', Colors.black),
            ('Red', const Color(0xffff5252)),
            ('Yellow', const Color(0xffffd740)),
            ('Green', const Color(0xff69f0ae)),
            ('Blue', const Color(0xff40c4ff)),
            ('Purple', const Color(0xffe040fb)),
            if (allowNone) ('None', Colors.transparent),
          ])
            IconButton(
              tooltip: '$title: $label',
              onPressed: () => onSelect(color),
              isSelected: color == selected,
              icon: color == Colors.transparent
                  ? const Icon(Icons.block)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      child: SizedBox.square(
                        dimension: 24,
                        child: color == selected
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: color.computeLuminance() > .45
                                    ? Colors.black
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
            ),
        ],
      ),
    ],
  );
}
