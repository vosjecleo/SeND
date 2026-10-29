import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/draft_store.dart';
import '../../services/custom_emoji.dart';
import '../../services/browser_lifecycle.dart' as browser;
import '../../services/keyboard_geometry.dart';
import '../../services/frame_diagnostics.dart';
import '../settings_screen.dart';
import '../call_and_chat_layout.dart';
import '../incoming_call_banner.dart';
import '../chat_shell.dart' show ForumView, openDiscussionById;
import '../advanced_chat_views.dart';
import 'mobile_details_panel.dart';
import 'mobile_navigation.dart';
import 'mobile_profile_sheet.dart';
import 'mobile_timeline.dart';
import 'mobile_voice_view.dart';

/// Phone-specific application shell.
///
/// Navigation, timeline, and details remain mounted as sliding physical layers
/// so opening a drawer never destroys a room's scroll state or draft. Matrix
/// SDK objects remain behind [ChatBackend], exactly as on desktop.
class MobileChatShell extends StatefulWidget {
  const MobileChatShell({required this.backend, super.key});
  final ChatBackend backend;

  @override
  State<MobileChatShell> createState() => _MobileChatShellState();
}

class _MobileChatShellState extends State<MobileChatShell>
    with WidgetsBindingObserver {
  bool _navigationVisible = true;
  int _threadRevision = 0;
  bool _detailsVisible = false;
  bool _voiceChatVisible = false;
  final Map<String, ({String text, List<CustomEmojiTextSpan> emojis})> _drafts =
      {};
  final DraftStore _draftStore = DraftStore();
  String? _lastRoomId;
  String? _lastSpaceId;
  int _roomOpenGeneration = 0;
  final Map<int, Offset> _pointerStarts = {};
  final _navigationMotion = ValueNotifier<double?>(null);
  double? get _navigationDragProgress => _navigationMotion.value;
  set _navigationDragProgress(double? value) => _navigationMotion.value = value;
  bool? _dragStartedWithNavigation;
  bool? _reportedConversationVisible;
  int _resumeGeneration = 0;
  DateTime? _backgroundedAt;
  KeyboardGeometry? _keyboardGeometry;
  FocusNode? _focusedWithKeyboard;
  FocusNode? _transientKeyboard;
  FocusNode? _keyboardToRestore;
  bool _restoreOnResume = false;
  bool _keyboardBackgrounded = false;
  bool _windowFocused = true;
  int _keyboardGeneration = 0;
  StreamSubscription<KeyboardGeometry>? _keyboardGeometrySubscription;
  StreamSubscription<bool>? _browserKeyboardVisibility;
  Timer? _timelineGestureReset;
  bool _suppressTimelineGestures = false;
  int _inboxRevision = 0;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _lastRoomId = backend.selectedRoom?.id;
    _lastSpaceId = backend.selectedSpaceId;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_rememberKeyboard);
    _keyboardGeometrySubscription = MobileKeyboardGeometry.changes.listen(
      _acceptKeyboardGeometry,
      onError: (Object error) {
        // Tests and unsupported hosts retain Flutter's normal inset handling.
      },
    );
    if (kIsWeb) {
      _browserKeyboardVisibility = browser.browserVisibilityChanges.listen((
        visible,
      ) {
        if (!visible) {
          _backgroundKeyboard();
          return;
        }
        _resumeKeyboard();
      });
    }
    backend.addListener(_backendChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backendChanged();
      unawaited(_refreshKeyboardGeometry());
    });
    unawaited(_restoreDrafts());
  }

  Future<void> _restoreDrafts() async {
    await _draftStore.initialize();
    for (final room in [...backend.rooms]) {
      final stored = _draftStore.read(room.id);
      if (stored == null) continue;
      final draft = customEmojiDraftFromDelta(stored.delta);
      if (draft.text.isNotEmpty) _drafts[room.id] = draft;
    }
    if (mounted) setState(() {});
  }

  void _backendChanged() {
    final request = backend.threadNavigationRequest;
    if (request != null && request.revision != _threadRevision) {
      _threadRevision = request.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && backend.selectedRoom?.id == request.roomId) {
          openDiscussionById(context, backend, request.roomId, request.rootId);
        }
      });
    }
    if (!mounted) return;
    if (backend.status == SessionStatus.signedOut) {
      _drafts.clear();
      unawaited(_draftStore.clear());
      return;
    }
    if (_inboxRevision != backend.inboxRequestRevision) {
      _inboxRevision = backend.inboxRequestRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showUnifiedInbox(
          context,
          backend,
          onOpen: (item) async {
            await backend.selectRoom(item.roomId);
            final room = backend.selectedRoom;
            if (room != null) await _openRoom(room);
          },
        );
      });
    }
    final roomId = backend.selectedRoom?.id;
    final spaceId = backend.selectedSpaceId;
    final roomChanged = roomId != _lastRoomId;
    final spaceChanged = spaceId != _lastSpaceId;
    if (!roomChanged && !spaceChanged) return;
    _lastRoomId = roomId;
    _lastSpaceId = spaceId;
    setState(() {
      if (roomChanged && roomId != null) {
        _navigationVisible = false;
        _detailsVisible = false;
        _voiceChatVisible = false;
      }
    });
  }

  @override
  void dispose() {
    _languageRecovery?.cancel();
    _browserKeyboardVisibility?.cancel();
    _keyboardGeometrySubscription?.cancel();
    FocusManager.instance.removeListener(_rememberKeyboard);
    WidgetsBinding.instance.removeObserver(this);
    backend.setConversationVisible(false);
    backend.removeListener(_backendChanged);
    unawaited(_draftStore.dispose());
    _timelineGestureReset?.cancel();
    _navigationMotion.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _rememberKeyboard();
      _transientKeyboard = _focusedWithKeyboard;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgroundKeyboard();
    }
    if (state == AppLifecycleState.paused) {
      _backgroundedAt ??= DateTime.now();
    }
    if (state != AppLifecycleState.resumed) return;
    final transient = _transientKeyboard;
    _transientKeyboard = null;
    if (!_keyboardBackgrounded &&
        transient?.hasFocus == true &&
        transient?.context != null) {
      _keyboardToRestore = transient;
      _restoreOnResume = true;
      _queueKeyboardRefresh();
    }
    _resumeKeyboard();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    // Focus-only transitions, including an IME language chooser, do not replace
    // navigation/focus state or open/close the input connection.
    if (backgroundedAt == null) return;
    _pointerStarts.clear();
    setState(() {
      _resumeGeneration++;
      _roomOpenGeneration++;
      _navigationDragProgress = null;
      _dragStartedWithNavigation = null;
    });
  }

  bool get _keyboardIsForeground => kIsWeb
      ? browser.browserApplicationVisible
      : WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _backgroundKeyboard() {
    if (_keyboardBackgrounded) return;
    _rememberKeyboard();
    _keyboardToRestore = _focusedWithKeyboard;
    _keyboardBackgrounded = true;
    _restoreOnResume = false;
    _keyboardGeneration++;
  }

  void _resumeKeyboard() {
    if (!_keyboardBackgrounded) return;
    _keyboardBackgrounded = false;
    _restoreOnResume = _keyboardToRestore != null;
    _keyboardGeometry = null;
    _queueKeyboardRefresh();
  }

  void _rememberKeyboard() {
    if (!mounted) return;
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.hasFocus != true ||
        focus?.context?.findAncestorStateOfType<EditableTextState>() == null) {
      // The browser/OS can park focus before its background event reaches this
      // observer. Keep the last editor then; explicit foreground focus changes
      // still clear it normally.
      if (_keyboardIsForeground && _windowFocused) {
        _focusedWithKeyboard = null;
      }
      return;
    }
    final geometry = _keyboardGeometry;
    final keyboardOpen = geometry?.settled == true
        ? geometry!.visible == true
        : MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardOpen) {
      _focusedWithKeyboard = focus;
    } else if (_keyboardIsForeground &&
        _windowFocused &&
        _keyboardGeometry?.settled == true) {
      _focusedWithKeyboard = null;
    }
  }

  void _acceptKeyboardGeometry(KeyboardGeometry geometry) {
    countUiDiagnostic('keyboard.geometry');
    if (!mounted) return;
    final oldSubtype = _keyboardGeometry?.inputSubtype;
    final languageChanged =
        oldSubtype != null &&
        geometry.inputSubtype != null &&
        oldSubtype != geometry.inputSubtype;
    final languageEditor = _focusedWithKeyboard ?? _languageEditor;
    if (languageChanged && languageEditor != null && !_keyboardBackgrounded) {
      _keyboardToRestore = languageEditor;
      _restoreOnResume = true;
      _languageRecoveryUntil = DateTime.now().add(
        const Duration(milliseconds: 500),
      );
      _languageRecovery?.cancel();
      _languageRecovery = Timer(const Duration(milliseconds: 500), () {
        if (mounted) unawaited(_refreshKeyboardGeometry());
      });
    }
    if (_keyboardGeometry != geometry) {
      setState(() => _keyboardGeometry = geometry);
    }
    _rememberKeyboard();
    if (!_restoreOnResume ||
        !_keyboardIsForeground ||
        !_windowFocused ||
        !geometry.settled) {
      return;
    }
    // This flag is consumed once. Declined restoration never discards focus,
    // sends TextInput.hide or leaves the layout dependent on a timeout.
    if (geometry.visible == true &&
        _languageRecoveryUntil != null &&
        DateTime.now().isBefore(_languageRecoveryUntil!)) {
      return;
    }
    _restoreOnResume = false;
    final focus = _keyboardToRestore;
    _keyboardToRestore = null;
    if (focus?.context == null) return;
    if (geometry.visible == true && focus!.hasFocus) return;
    final generation = _keyboardGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _keyboardGeneration ||
          !_keyboardIsForeground ||
          !_windowFocused ||
          focus?.context == null) {
        return;
      }
      if (geometry.visible == true) {
        focus!.requestFocus();
      } else {
        focus!.context!
            .findAncestorStateOfType<EditableTextState>()
            ?.requestKeyboard();
      }
    });
  }

  bool _keyboardRefreshQueued = false;
  Timer? _languageRecovery;
  DateTime? _languageRecoveryUntil;
  FocusNode? _languageEditor;
  void _queueKeyboardRefresh() {
    if (_keyboardRefreshQueued || !mounted) return;
    _keyboardRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardRefreshQueued = false;
      if (mounted) unawaited(_refreshKeyboardGeometry());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _refreshKeyboardGeometry() async {
    final generation = _keyboardGeneration;
    final geometry = await MobileKeyboardGeometry.refresh();
    if (mounted && generation == _keyboardGeneration && geometry != null) {
      _acceptKeyboardGeometry(geometry);
    }
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    _windowFocused = event.state == ViewFocusState.focused;
    if (!_windowFocused) {
      _rememberKeyboard();
      _languageEditor = _focusedWithKeyboard;
    } else {
      // A refreshed measurement is safe on focus regain; reopening IME is only
      // permitted by the separate real-background flag.
      _queueKeyboardRefresh();
    }
  }

  @override
  void didChangeMetrics() {
    _queueKeyboardRefresh();
  }

  Future<void> _openRoom(RoomSummary room) async {
    final generation = ++_roomOpenGeneration;
    await backend.selectRoom(room.id);
    if (generation != _roomOpenGeneration) return;
    if (!mounted) return;
    setState(() {
      _lastRoomId = room.id;
      _navigationVisible = false;
      _detailsVisible = false;
      _voiceChatVisible = false;
    });
  }

  void _showSettings() => showDeltiecordSettings(context, backend);

  @override
  Widget build(BuildContext context) {
    countUiDiagnostic('shell.build');
    final room = backend.selectedRoom;
    _reportConversationVisibility(
      room != null &&
          ((!room.isVoice && !_detailsVisible) ||
              (_detailsVisible && _voiceChatVisible)) &&
          _navigationProgress <= 0.001,
    );
    final canSystemPop = _navigationVisible && !_detailsVisible;
    final shell = PopScope(
      canPop: canSystemPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_detailsVisible) {
          setState(() => _detailsVisible = false);
        } else if (!_navigationVisible) {
          setState(() => _navigationVisible = true);
        }
      },
      child: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          // Raw pointer tracking deliberately observes (but does not win) the
          // gesture arena. Message rows may still claim a left drag for reply,
          // while a right drag on the timeline opens navigation.
          onPointerDown: (event) {
            _transientKeyboard = null;
            _languageEditor = null;
            _languageRecoveryUntil = null;
            _languageRecovery?.cancel();
            _keyboardGeneration++;
            _restoreOnResume = false;
            _keyboardToRestore = null;
            _queueKeyboardRefresh();
            _pointerStarts[event.pointer] = event.position;
          },
          onPointerMove: (event) {
            final start = _pointerStarts[event.pointer];
            if (start == null || _detailsVisible || room == null) return;
            final shell = context.findRenderObject();
            if (_navigationVisible &&
                shell is RenderBox &&
                shell.globalToLocal(start).dx < 70) {
              return;
            }
            // Keep text-selection drags out of navigation. While editing, the
            // edge gesture and explicit navigation button remain available.
            final editor = FocusManager.instance.primaryFocus?.context
                ?.findAncestorStateOfType<EditableTextState>()
                ?.context
                .findRenderObject();
            if (editor is RenderBox &&
                editor.hasSize &&
                (editor.localToGlobal(Offset.zero) & editor.size)
                    .inflate(24)
                    .contains(start)) {
              return;
            }
            final delta = event.position - start;
            if (delta.dx.abs() < 6 || delta.dx.abs() < delta.dy.abs() * 1.15) {
              return;
            }
            final startedVisible =
                _dragStartedWithNavigation ?? _navigationVisible;
            if ((startedVisible && delta.dx >= 0) ||
                (!startedVisible && delta.dx <= 0)) {
              return;
            }
            final startingDrag = _navigationDragProgress == null;
            if (startingDrag) {
              FocusManager.instance.primaryFocus?.unfocus();
              _timelineGestureReset?.cancel();
            }
            final width = MediaQuery.sizeOf(context).width;
            final progress = startedVisible
                ? (1 + delta.dx / width).clamp(0.0, 1.0)
                : (delta.dx / width).clamp(0.0, 1.0);
            _dragStartedWithNavigation = startedVisible;
            _navigationDragProgress = progress;
            if (startingDrag) setState(() => _suppressTimelineGestures = true);
          },
          onPointerCancel: (event) {
            _pointerStarts.remove(event.pointer);
            if (_navigationDragProgress != null) {
              setState(() {
                _navigationDragProgress = null;
                _dragStartedWithNavigation = null;
              });
              _releaseTimelineGesturesLater();
            }
          },
          onPointerUp: (event) {
            final start = _pointerStarts.remove(event.pointer);
            if (start == null) return;
            final progress = _navigationDragProgress;
            final startedVisible = _dragStartedWithNavigation;
            if (progress != null && startedVisible != null) {
              setState(() {
                _navigationVisible = startedVisible
                    ? progress >= 0.78
                    : progress >= 0.18;
                _navigationDragProgress = null;
                _dragStartedWithNavigation = null;
              });
              _releaseTimelineGesturesLater();
              return;
            }
            final delta = event.position - start;
            if (delta.dx.abs() < 72 || delta.dx.abs() < delta.dy.abs() * 1.25) {
              return;
            }
            if (_detailsVisible && delta.dx > 0) {
              setState(() => _detailsVisible = false);
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: _NavigationSlide(
                  motion: _navigationMotion,
                  visible: _navigationVisible,
                  closedX: 0,
                  openX: room == null ? 0 : .12,
                  duration: _duration,
                  child: room == null
                      ? const _NoRoomSelected()
                      : room.isVoice
                      ? MobileVoiceView(
                          backend: backend,
                          room: room,
                          onOpenNavigation: () =>
                              setState(() => _navigationVisible = true),
                          onOpenDetails: () => setState(() {
                            _voiceChatVisible = false;
                            _detailsVisible = true;
                          }),
                          onOpenChat: () => setState(() {
                            _voiceChatVisible = true;
                            _detailsVisible = true;
                          }),
                        )
                      : room.presentation == RoomPresentation.forum
                      ? SafeArea(
                          child: ForumView(
                            backend: backend,
                            room: room,
                            onOpenNavigation: () =>
                                setState(() => _navigationVisible = true),
                          ),
                        )
                      : CallAndChatLayout(
                          call: backend.activeVoiceRoomId == room.id
                              ? MobileVoiceView(
                                  backend: backend,
                                  room: room,
                                  onOpenNavigation: () =>
                                      setState(() => _navigationVisible = true),
                                  onOpenDetails: () =>
                                      setState(() => _detailsVisible = true),
                                )
                              : null,
                          chat: MobileTimelineView(
                            key: ValueKey('mobile-room-${room.id}'),
                            backend: backend,
                            room: room,
                            onOpenNavigation: () =>
                                setState(() => _navigationVisible = true),
                            onOpenDetails: () =>
                                setState(() => _detailsVisible = true),
                            onOpenSettings: _showSettings,
                            navigationGestureActive:
                                _navigationDragProgress != null ||
                                _suppressTimelineGestures,
                            initialDraft: _drafts[room.id]?.text ?? '',
                            initialCustomEmojis:
                                _drafts[room.id]?.emojis ?? const [],
                            onDraftChanged: (value) {
                              if (value.text.isEmpty) {
                                _drafts.remove(room.id);
                                _draftStore.remove(room.id);
                              } else {
                                _drafts[room.id] = value;
                                _draftStore.write(
                                  room.id,
                                  customEmojiDraftDelta(
                                    value.text,
                                    value.emojis,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                ),
              ),
              Positioned.fill(
                child: _NavigationSlide(
                  motion: _navigationMotion,
                  visible: _navigationVisible,
                  closedX: -1,
                  openX: 0,
                  duration: _duration,
                  child: IgnorePointer(
                    ignoring: _navigationProgress < 0.02,
                    child: Material(
                      elevation: 12,
                      child: MobileNavigationPanel(
                        key: ValueKey(
                          'mobile-navigation-panel-$_resumeGeneration',
                        ),
                        backend: backend,
                        onOpenRoom: _openRoom,
                        onOpenSettings: _showSettings,
                        onOpenProfile: () {
                          final userId = backend.userId;
                          if (userId == null) return;
                          showMobileProfileSheet(
                            context,
                            backend,
                            userId,
                            onEditOwnProfile: _showSettings,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (room != null)
                Positioned.fill(
                  child: AnimatedSlide(
                    offset: _detailsVisible ? Offset.zero : const Offset(1, 0),
                    duration: _duration,
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      ignoring: !_detailsVisible,
                      child: Material(
                        elevation: 14,
                        child: _voiceChatVisible
                            ? MobileTimelineView(
                                key: ValueKey('voice-chat-${room.id}'),
                                backend: backend,
                                room: room,
                                onOpenNavigation: () =>
                                    setState(() => _detailsVisible = false),
                                onOpenDetails: () =>
                                    setState(() => _voiceChatVisible = false),
                                onOpenSettings: _showSettings,
                                navigationGestureActive: false,
                                initialDraft: _drafts[room.id]?.text ?? '',
                                initialCustomEmojis:
                                    _drafts[room.id]?.emojis ?? const [],
                                onDraftChanged: (draft) {
                                  _drafts[room.id] = draft;
                                  _draftStore.write(
                                    room.id,
                                    customEmojiDraftDelta(
                                      draft.text,
                                      draft.emojis,
                                    ),
                                  );
                                },
                              )
                            : MobileDetailsPanel(
                                backend: backend,
                                room: room,
                                onDismiss: () =>
                                    setState(() => _detailsVisible = false),
                              ),
                      ),
                    ),
                  ),
                ),
              if (backend.activeVoiceRoomId != null &&
                  room?.id != backend.activeVoiceRoomId &&
                  !_navigationVisible)
                Positioned(
                  right: 12,
                  bottom: 92,
                  child: MobileCallIsland(
                    backend: backend,
                    onOpen: () async {
                      final voiceRoom = backend.rooms
                          .where((item) => item.id == backend.activeVoiceRoomId)
                          .firstOrNull;
                      if (voiceRoom != null) await _openRoom(voiceRoom);
                    },
                  ),
                ),
              if (backend.incomingCall != null)
                Positioned.fill(child: IncomingCallBanner(backend: backend)),
            ],
          ),
        ),
      ),
    );
    final media = MediaQuery.of(context);
    final geometry = _keyboardGeometry;
    var keyboardMedia = media;
    final physicalHeight = View.of(context).physicalSize.height;
    if (_keyboardIsForeground &&
        _windowFocused &&
        geometry?.settled == true &&
        physicalHeight > 0) {
      final bottom = geometry!.bottomForView(physicalHeight, media.size.height);
      keyboardMedia = media.copyWith(
        viewInsets: media.viewInsets.copyWith(bottom: bottom),
        padding: media.padding.copyWith(
          bottom: (media.viewPadding.bottom - bottom).clamp(
            0.0,
            double.infinity,
          ),
        ),
      );
    }
    // Keep this wrapper present even while geometry is unknown. Changing the
    // subtree shape would dispose the composer and its input connection.
    return MediaQuery(data: keyboardMedia, child: shell);
  }

  void _releaseTimelineGesturesLater() {
    _timelineGestureReset?.cancel();
    _timelineGestureReset = Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _suppressTimelineGestures = false);
    });
  }

  Duration get _duration => backend.preferences.reducedMotion
      ? Duration.zero
      : const Duration(milliseconds: 220);

  double get _navigationProgress =>
      _navigationDragProgress ?? (_navigationVisible ? 1 : 0);

  void _reportConversationVisibility(bool visible) {
    visible = visible && ModalRoute.of(context)?.isCurrent != false;
    if (_reportedConversationVisible == visible) return;
    _reportedConversationVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedConversationVisible != visible) return;
      backend.setConversationVisible(visible);
    });
  }
}

/// Drag frames update only the panel transform, not its room/list contents.
class _NavigationSlide extends StatelessWidget {
  const _NavigationSlide({
    required this.motion,
    required this.visible,
    required this.closedX,
    required this.openX,
    required this.duration,
    required this.child,
  });
  final ValueListenable<double?> motion;
  final bool visible;
  final double closedX, openX;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double?>(
    valueListenable: motion,
    child: child,
    builder: (context, drag, child) {
      final progress = drag ?? (visible ? 1.0 : 0.0);
      return AnimatedSlide(
        offset: Offset(closedX + (openX - closedX) * progress, 0),
        duration: drag == null ? duration : Duration.zero,
        curve: Curves.easeOutCubic,
        child: child,
      );
    },
  );
}

class _NoRoomSelected extends StatelessWidget {
  const _NoRoomSelected();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 50),
          SizedBox(height: 12),
          Text('Choose a room to start chatting'),
        ],
      ),
    ),
  );
}
