import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'threshold_feedback.dart';

/// Archive is a Home-list mode, not a separate page or dialog.
Future<void> openArchive(
  BuildContext context,
  ChatBackend backend, {
  Future<void> Function(RoomSummary)? onOpenRoom,
}) async => backend.setArchiveOpen(true);

class ArchivePullList extends StatefulWidget {
  const ArchivePullList({
    required this.backend,
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
    this.padding,
    this.enabled = true,
    this.onOpenRoom,
    this.onOpenArchive,
    this.emptyLabel = 'No joined rooms',
    super.key,
  });
  final ChatBackend backend;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int? Function(Key)? findChildIndexCallback;
  final EdgeInsetsGeometry? padding;
  final bool enabled;
  final Future<void> Function(RoomSummary)? onOpenRoom;
  final VoidCallback? onOpenArchive;
  final String emptyLabel;
  @override
  State<ArchivePullList> createState() => _ArchivePullListState();
}

class _ArchivePullListState extends State<ArchivePullList>
    with SingleTickerProviderStateMixin {
  static const _rowHeight = 56.0, _threshold = 104.0, _maximumPull = 176.0;
  final _scroll = ScrollController();
  late final _motion = AnimationController.unbounded(vsync: this);
  bool _shown = false, _hiding = false, _wheel = false;
  double _homeOffset = 0;
  Timer? _wheelEnd;
  @override
  void dispose() {
    _wheelEnd?.cancel();
    _motion.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArchivePullList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _wheelEnd?.cancel();
      if (!widget.enabled && _scroll.hasClients) _homeOffset = _scroll.offset;
      _motion.value = widget.enabled && _shown ? _rowHeight : 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            (widget.enabled ? _homeOffset : 0)
                .clamp(0, _scroll.position.maxScrollExtent)
                .toDouble(),
          );
        }
      });
    }
  }

  void _open() {
    if (widget.onOpenArchive != null) {
      widget.onOpenArchive!();
    } else {
      openArchive(context, widget.backend);
    }
  }

  void _pull(double delta) {
    if (!widget.enabled || _shown) return;
    _motion.stop();
    final resistance = delta > 0 ? .7 / (1 + _motion.value / 180) : 1.0;
    _motion.value = (_motion.value + delta * resistance).clamp(0, _maximumPull);
  }

  void _animate(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = target;
      return;
    }
    _motion.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _release() {
    if (!mounted || _shown || _motion.value <= 0) return;
    final reveal = _motion.value >= _threshold;
    if (reveal) setState(() => _shown = true);
    _animate(reveal ? _rowHeight : 0);
  }

  bool _notification(ScrollNotification event) {
    if (!widget.enabled || event.depth != 0) return false;
    if (!_shown) {
      if (event is ScrollStartNotification && event.dragDetails != null) {
        _wheelEnd?.cancel();
        _wheel = false;
        _motion.stop();
      }
      if (event is OverscrollNotification &&
          event.dragDetails != null &&
          event.metrics.pixels <= .5) {
        _pull(-event.overscroll);
      } else if (event is ScrollUpdateNotification &&
          event.dragDetails != null &&
          _motion.value > 0 &&
          event.scrollDelta != null) {
        // A reversed drag consumes the reveal before scrolling the chats.
        _pull(-event.scrollDelta!);
      }
      if (event is ScrollEndNotification && !(_wheelEnd?.isActive ?? false)) {
        _release();
      }
    } else if (!_hiding && event.metrics.pixels >= _rowHeight) {
      _hiding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final offset = _scroll.hasClients ? _scroll.offset : 0.0;
        setState(() => _shown = false);
        _motion.value = 0;
        if (_scroll.hasClients) {
          _scroll.jumpTo(
            (offset - _rowHeight)
                .clamp(0, _scroll.position.maxScrollExtent)
                .toDouble(),
          );
        }
        _hiding = false;
      });
    }
    return false;
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (!widget.enabled ||
        _shown ||
        event is! PointerScrollEvent ||
        !_scroll.hasClients ||
        _scroll.offset > .5 ||
        event.scrollDelta.dy >= 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      _wheel = true;
      _pull(-event.scrollDelta.dy);
      _wheelEnd?.cancel();
      _wheelEnd = Timer(const Duration(milliseconds: 180), _release);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.enabled && _shown;
    final list = ListView.builder(
      key: PageStorageKey('chat-list-${widget.enabled ? 'home' : 'archive'}'),
      controller: _scroll,
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: widget.padding,
      itemCount: widget.itemCount + (visible ? 1 : 0),
      findChildIndexCallback: widget.findChildIndexCallback == null
          ? null
          : (key) {
              if (key == const ValueKey('home-archive-entry')) {
                return visible ? 0 : null;
              }
              final found = widget.findChildIndexCallback!(key);
              return found == null ? null : found + (visible ? 1 : 0);
            },
      itemBuilder: (context, index) {
        if (visible && index == 0) {
          return SizedBox(
            key: const ValueKey('home-archive-entry'),
            height: _rowHeight,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              horizontalTitleGap: 12,
              leading: const SizedBox.square(
                dimension: 44,
                child: Icon(Icons.archive_outlined),
              ),
              title: const Text('Archive'),
              trailing: Text('${widget.backend.archivedRooms.length}'),
              onTap: _open,
            ),
          );
        }
        return widget.itemBuilder(context, index - (visible ? 1 : 0));
      },
    );
    return Semantics(
      customSemanticsActions: widget.enabled
          ? {CustomSemanticsAction(label: 'Open Archive'): _open}
          : null,
      child: Listener(
        onPointerSignal: _pointerSignal,
        child: NotificationListener<ScrollNotification>(
          onNotification: _notification,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              overscroll: false,
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, child) {
                  final pull = widget.enabled ? _motion.value : 0.0;
                  final ready = pull >= _threshold;
                  return Stack(
                    children: [
                      if (widget.enabled && !visible && pull > 0)
                        Positioned(
                          left: 8,
                          right: 8,
                          top: 0,
                          height: pull,
                          child: Opacity(
                            opacity: ((pull - 18) / 45).clamp(0, 1),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ThresholdFeedbackIcon(
                                  active: ready,
                                  haptics: !_wheel,
                                  icon: ready
                                      ? Icons.archive_outlined
                                      : Icons.keyboard_double_arrow_down,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  ready
                                      ? 'Release to show Archive'
                                      : (_wheel
                                            ? 'Keep scrolling for Archive'
                                            : 'Keep pulling for Archive'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: Transform.translate(
                          offset: Offset(0, pull - (visible ? _rowHeight : 0)),
                          child: child,
                        ),
                      ),
                      if (widget.itemCount == 0 && !visible)
                        Center(
                          child: IgnorePointer(child: Text(widget.emptyLabel)),
                        ),
                    ],
                  );
                },
                child: list,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
