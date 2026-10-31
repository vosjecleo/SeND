import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/physics.dart';
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
    this.alwaysVisible = false,
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
  final bool alwaysVisible;
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
  int _motionGeneration = 0;
  bool get _desktop => widget.alwaysVisible;
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
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.alwaysVisible != widget.alwaysVisible) {
      _motionGeneration++;
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
    if (!widget.enabled || _shown || _desktop) return;
    _motionGeneration++;
    _motion.stop();
    final resistance = delta > 0 ? .7 / (1 + _motion.value / 180) : 1.0;
    _motion.value = (_motion.value + delta * resistance).clamp(0, _maximumPull);
  }

  void _animate(double target) {
    final generation = ++_motionGeneration;
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = target;
      return;
    }
    unawaited(
      _motion
          .animateWith(
            SpringSimulation(
              SpringDescription.withDampingRatio(
                mass: 1,
                stiffness: 420,
                ratio: .9,
              ),
              _motion.value,
              target,
              0,
            ),
          )
          .then<void>((_) {
            if (mounted && generation == _motionGeneration) {
              _motion.value = target;
            }
          }),
    );
  }

  void _release() {
    if (!mounted || _desktop || _shown || _motion.value <= 0) return;
    final reveal = _motion.value >= _threshold;
    if (reveal) setState(() => _shown = true);
    _animate(reveal ? _rowHeight : 0);
  }

  bool _notification(ScrollNotification event) {
    if (!widget.enabled || _desktop || event.depth != 0) return false;
    if (!_shown) {
      if (event is ScrollStartNotification && event.dragDetails != null) {
        _wheelEnd?.cancel();
        _wheel = false;
        _motionGeneration++;
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
        _desktop ||
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
    final desktop = _desktop;
    final visible = widget.enabled && (desktop || _shown);
    final rowHeight = desktop ? 36.0 : _rowHeight;
    // A permanent leading slot avoids recycling GIF decoders when revealing
    // or hiding Archive. The visible row itself scrolls with the chats.
    final listEntry = widget.enabled;
    Widget entry() => SizedBox(
      key: const ValueKey('home-archive-entry'),
      height: rowHeight,
      child: ListTile(
        dense: desktop,
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        horizontalTitleGap: 12,
        leading: const SizedBox.square(
          dimension: 28,
          child: Icon(Icons.archive_outlined, size: 20),
        ),
        title: const Text('Archive'),
        trailing: Text('${widget.backend.archivedRooms.length}'),
        onTap: _open,
      ),
    );
    final list = ListView.builder(
      key: PageStorageKey('chat-list-${widget.enabled ? 'home' : 'archive'}'),
      controller: _scroll,
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: widget.padding,
      itemCount: widget.itemCount + (listEntry ? 1 : 0),
      findChildIndexCallback: widget.findChildIndexCallback == null
          ? null
          : (key) {
              if (key == const ValueKey('home-archive-slot')) {
                return listEntry ? 0 : null;
              }
              final found = widget.findChildIndexCallback!(key);
              return found == null ? null : found + (listEntry ? 1 : 0);
            },
      itemBuilder: (context, index) {
        if (listEntry && index == 0) {
          return KeyedSubtree(
            key: const ValueKey('home-archive-slot'),
            child: visible ? entry() : const SizedBox.shrink(),
          );
        }
        return widget.itemBuilder(context, index - (listEntry ? 1 : 0));
      },
    );
    if (desktop) {
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Stack(
          children: [
            Positioned.fill(child: list),
            if (widget.itemCount == 0)
              Center(child: IgnorePointer(child: Text(widget.emptyLabel))),
          ],
        ),
      );
    }
    return Semantics(
      customSemanticsActions: widget.enabled
          ? {CustomSemanticsAction(label: 'Open Archive'): _open}
          : null,
      child: Listener(
        onPointerSignal: _pointerSignal,
        // Navigation and gesture cancellation can prevent a ScrollEnd from
        // reaching the list. Never leave the reveal parked under the finger.
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
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
                  final pull = desktop
                      ? (visible ? rowHeight : 0.0)
                      : widget.enabled
                      ? _motion.value.clamp(0.0, _maximumPull)
                      : 0.0;
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
                            child: ClipRect(
                              child: OverflowBox(
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
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
                          ),
                        ),
                      Positioned.fill(
                        // Keep the active scrollable mounted when the pull
                        // hint is inserted before it in the stack.
                        key: const ValueKey('archive-pull-scrollable'),
                        child: Transform.translate(
                          offset: Offset(0, pull - (visible ? rowHeight : 0)),
                          child: child,
                        ),
                      ),
                      if (widget.itemCount == 0 && (!visible || desktop))
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
