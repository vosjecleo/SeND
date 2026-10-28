import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../backend/chat_backend.dart';

class ProfileWatch extends StatefulWidget {
  const ProfileWatch({
    required this.backend,
    required this.id,
    required this.child,
    this.expanded = false,
    super.key,
  });
  final ChatBackend? backend;
  final String id;
  final Widget child;
  final bool expanded;
  @override
  State<ProfileWatch> createState() => _ProfileWatchState();
}

class _ProfileWatchState extends State<ProfileWatch> {
  VoidCallback? _stop;
  bool _enabled = true;
  bool _queued = false, _wasVisible = false;
  ScrollPosition? _scroll;
  void _checkVisibility() {
    if (_queued || !mounted) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted) return;
      final visible = _visible();
      if (visible && !_wasVisible) {
        widget.backend?.refreshVisibleAvatar(widget.id);
      }
      _wasVisible = visible;
    });
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() => _stop = widget.backend?.watchProfile(
    widget.id,
    isVisible: _visible,
    expanded: widget.expanded,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled;
    final scroll = Scrollable.maybeOf(context)?.position;
    if (!identical(scroll, _scroll)) {
      _scroll?.removeListener(_checkVisibility);
      _scroll = scroll;
      scroll?.addListener(_checkVisibility);
    }
    _checkVisibility();
  }

  @override
  void didUpdateWidget(ProfileWatch old) {
    super.didUpdateWidget(old);
    if (old.backend != widget.backend ||
        old.id != widget.id ||
        old.expanded != widget.expanded) {
      _stop?.call();
      _subscribe();
      _wasVisible = false;
      _checkVisibility();
    }
  }

  bool _visible() {
    if (!mounted || !_enabled) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    final viewport = RenderAbstractViewport.maybeOf(box);
    final window = Offset.zero & MediaQuery.sizeOf(context);
    if (!bounds.overlaps(window)) return false;
    if (viewport is RenderBox && (viewport as RenderBox).hasSize) {
      final frame = viewport as RenderBox;
      return bounds.overlaps(frame.localToGlobal(Offset.zero) & frame.size);
    }
    return true;
  }

  @override
  void dispose() {
    _scroll?.removeListener(_checkVisibility);
    _stop?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
