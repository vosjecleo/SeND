import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Opt-in diagnostic logs contain action names and pointer events, never text.
class SelectionToolbar extends StatefulWidget {
  const SelectionToolbar({
    required this.anchors,
    required this.items,
    super.key,
  });
  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> items;
  static const diagnostics = bool.fromEnvironment('SEND_INPUT_DIAGNOSTICS');

  @override
  State<SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends State<SelectionToolbar> {
  Object? _appearance;
  List<Object?> _actions = const [];
  List<Widget> _buttons = const [];

  @override
  Widget build(BuildContext context) {
    final appearance = (
      Theme.of(context),
      Localizations.localeOf(context),
      Directionality.of(context),
      MediaQuery.textScalerOf(context),
    );
    final actions = widget.items
        .map<Object?>((item) => (item.type, item.label, item.onPressed != null))
        .toList();
    // Flutter's overflow toolbar resets its keyed button subtree whenever the
    // button widget list changes. Keep widgets stable through unrelated sync
    // updates, while invoking current callbacks and refreshing real changes.
    if (_appearance != appearance || !listEquals(_actions, actions)) {
      _appearance = appearance;
      _actions = actions;
      _buttons = AdaptiveTextSelectionToolbar.getAdaptiveButtons(context, [
        for (var i = 0; i < widget.items.length; i++)
          ContextMenuButtonItem(
            type: widget.items[i].type,
            label: widget.items[i].label,
            onPressed: widget.items[i].onPressed == null
                ? null
                : () {
                    if (SelectionToolbar.diagnostics) {
                      debugPrint(
                        'SeND toolbar action=${widget.items[i].type.name}',
                      );
                    }
                    widget.items[i].onPressed?.call();
                  },
          ),
      ]).toList();
    }
    final toolbar = AdaptiveTextSelectionToolbar(
      anchors: widget.anchors,
      children: _buttons,
    );
    return TextFieldTapRegion(
      child: SelectionToolbar.diagnostics
          ? Listener(
              onPointerDown: (event) => debugPrint(
                'SeND toolbar down kind=${event.kind.name} buttons=${event.buttons}',
              ),
              onPointerUp: (_) => debugPrint('SeND toolbar up'),
              onPointerCancel: (_) => debugPrint('SeND toolbar cancel'),
              child: toolbar,
            )
          : toolbar,
    );
  }
}
