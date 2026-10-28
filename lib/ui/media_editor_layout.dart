import 'package:flutter/material.dart';

class MediaEditorTool {
  const MediaEditorTool(this.title, this.icon, this.content);
  final String title;
  final IconData icon;
  final Widget content;
}

class MediaEditorLayout extends StatelessWidget {
  const MediaEditorLayout({
    required this.preview,
    required this.tools,
    required this.selected,
    required this.onSelect,
    required this.spoiler,
    required this.onSpoiler,
    this.disabled = false,
    super.key,
  });
  final Widget preview;
  final List<MediaEditorTool> tools;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool spoiler, disabled;
  final VoidCallback onSpoiler;

  Widget _spoilerButton(BuildContext context) => IconButton(
    tooltip: spoiler ? 'Remove spoiler' : 'Mark as spoiler',
    isSelected: spoiler,
    onPressed: disabled ? null : onSpoiler,
    icon: const Icon(Icons.visibility_outlined),
    selectedIcon: const Icon(Icons.visibility_off_outlined),
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final image = Stack(
        key: const ValueKey('editor-preview-region'),
        fit: StackFit.expand,
        children: [
          preview,
          if (spoiler)
            IgnorePointer(
              child: ColoredBox(
                key: const ValueKey('editor-spoiler-haze'),
                color: const Color(0x55000000),
                child: const Center(
                  child: Icon(
                    Icons.visibility_off_outlined,
                    size: 42,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
        ],
      );
      if (c.maxWidth >= 850) {
        return Row(
          children: [
            Expanded(child: image),
            SizedBox(
              width: 390,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < tools.length; i++) ...[
                      if (i > 0) const Divider(height: 32),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: disabled ? null : () => onSelect(i),
                          icon: Icon(tools[i].icon),
                          label: Text(tools[i].title),
                          style: TextButton.styleFrom(
                            foregroundColor: i == selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Listener(
                        onPointerDown: (_) {
                          if (!disabled && i != selected) onSelect(i);
                        },
                        child: IgnorePointer(
                          ignoring: disabled,
                          child: tools[i].content,
                        ),
                      ),
                    ],
                    const Divider(height: 32),
                    Row(
                      children: [
                        _spoilerButton(context),
                        const Text('Spoiler'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: image),
          const Divider(height: 1),
          SizedBox(
            height: (c.maxHeight * .24).clamp(104.0, 184.0),
            child: SingleChildScrollView(
              key: ValueKey('editor-tool-$selected'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: IgnorePointer(
                ignoring: disabled,
                child: tools[selected].content,
              ),
            ),
          ),
          const Divider(height: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < tools.length; i++)
                IconButton(
                  tooltip: tools[i].title,
                  isSelected: selected == i,
                  style: selected == i
                      ? IconButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.light
                              ? Colors.black.withValues(alpha: .65)
                              : Colors.white.withValues(alpha: .12),
                        )
                      : null,
                  color: selected == i
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: disabled ? null : () => onSelect(i),
                  icon: Icon(
                    tools[i].icon,
                    size: selected == i ? 28 : 24,
                    weight: selected == i ? 700 : 400,
                    shadows: selected == i
                        ? const [
                            Shadow(color: Colors.white, offset: Offset(.35, 0)),
                            Shadow(
                              color: Colors.white,
                              offset: Offset(-.35, 0),
                            ),
                          ]
                        : null,
                  ),
                ),
              _spoilerButton(context),
            ],
          ),
        ],
      );
    },
  );
}
