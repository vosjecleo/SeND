import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/draft_store.dart';
import '../../services/custom_emoji.dart';
import '../../services/browser_lifecycle.dart' as browser;
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
  double? _navigationDragProgress;
  bool? _dragStartedWithNavigation;
  bool? _reportedConversationVisible;
  int _resumeGeneration = 0;
  DateTime? _backgroundedAt;
  bool _ignoreStaleKeyboardInsets = false;
  int _keyboardResumeCheck = 0;
  Timer? _keyboardResumeTimer;
  FocusNode? _keyboardFocus;
  bool _restoringKeyboard = false;
  int _keyboardVisibilityRetries = 0;
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
    backend.addListener(_backendChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _backendChanged());
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
    _keyboardResumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    backend.setConversationVisible(false);
    backend.removeListener(_backendChanged);
    unawaited(_draftStore.dispose());
    _timelineGestureReset?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _rememberKeyboard();
    }
    if (state == AppLifecycleState.paused) {
      _backgroundedAt ??= DateTime.now();
    }
    if (state != AppLifecycleState.resumed) return;
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    // IME pickers can produce inactive/resumed without pausing the app.
    // Do not rebuild focus scopes or dismiss input for those transitions.
    final keyboardGeneration = ++_keyboardResumeCheck;
    _keyboardResumeTimer?.cancel();
    _restoringKeyboard = false;
    _keyboardVisibilityRetries = 0;
    _keyboardResumeTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_checkResumedKeyboard(keyboardGeneration));
    });
    if (backgroundedAt == null) return;
    // Pointer streams can be interrupted when Android freezes the activity.
    // Keep durable navigation state, but discard only transient gesture state
    // so an orphaned pointer cannot leave the Space rail non-interactive.
    _pointerStarts.clear();
    setState(() {
      _resumeGeneration++;
      _roomOpenGeneration++;
      // A suspended room-open future must not suppress subsequent backend
      // selection notifications after Android thaws the activity.
      _navigationDragProgress = null;
      _dragStartedWithNavigation = null;
    });
    // Rebuilding the navigation subtree reconciles the rail and room card
    // after Android recreates its surface. Do not re-select the Space through
    // the backend here: Space selection intentionally clears the active room.
  }

  Future<void> _checkResumedKeyboard(int generation) async {
    // Let Android restore its window before comparing its actual IME state
    // with Flutter's last insets. A language picker must retain focus.
    if (!mounted ||
        generation != _keyboardResumeCheck ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      final visible = await _keyboardVisible();
      if (!mounted || generation != _keyboardResumeCheck) return;
      if (visible == true) {
        if (_ignoreStaleKeyboardInsets) {
          setState(() => _ignoreStaleKeyboardInsets = false);
        }
        _keyboardFocus = null;
        _restoringKeyboard = false;
        return;
      }
      // A system language chooser may still own the window. Unknown visibility
      // is not a reason to discard its input connection.
      if (visible == null) {
        if (_keyboardVisibilityRetries++ < 8) {
          _keyboardResumeTimer = Timer(const Duration(milliseconds: 250), () {
            unawaited(_checkResumedKeyboard(generation));
          });
        }
        return;
      }
      final focus = _keyboardFocus;
      if (focus != null &&
          focus.context != null &&
          focus.hasFocus &&
          !_restoringKeyboard) {
        _restoringKeyboard = true;
        final editor = focus.context!
            .findAncestorStateOfType<EditableTextState>();
        if (editor != null) {
          editor.requestKeyboard();
        } else {
          await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        }
        if (!mounted || generation != _keyboardResumeCheck) return;
        _keyboardResumeTimer = Timer(const Duration(milliseconds: 700), () {
          unawaited(_checkResumedKeyboard(generation));
        });
        return;
      }
      // Restoration was declined or input was dismissed. Remove stale space
      // throughout the nested layout instead of leaving the composer floating.
      if (focus?.hasFocus == true) focus!.unfocus();
      _keyboardFocus = null;
      _restoringKeyboard = false;
      if (MediaQuery.viewInsetsOf(context).bottom > 0) {
        setState(() => _ignoreStaleKeyboardInsets = true);
      }
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } on PlatformException {
      // Older Android versions may not expose reliable IME visibility.
    } on MissingPluginException {
      // Other platforms retain their own keyboard/inset lifecycle.
    }
  }

  void _rememberKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.hasFocus == true &&
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      _keyboardFocus = focus;
    }
  }

  Future<bool?> _keyboardVisible() async {
    if (kIsWeb) return browser.browserKeyboardVisible;
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    return const MethodChannel(
      'net.deltie.deltiecord/composer',
    ).invokeMethod<bool>('keyboardVisible');
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.unfocused) {
      _rememberKeyboard();
    } else if (_keyboardFocus != null || _ignoreStaleKeyboardInsets) {
      final generation = ++_keyboardResumeCheck;
      _keyboardResumeTimer?.cancel();
      _restoringKeyboard = false;
      _keyboardVisibilityRetries = 0;
      _keyboardResumeTimer = Timer(const Duration(milliseconds: 350), () {
        unawaited(_checkResumedKeyboard(generation));
      });
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !_ignoreStaleKeyboardInsets) return;
    if (View.of(context).viewInsets.bottom <= 0) {
      setState(() => _ignoreStaleKeyboardInsets = false);
    } else {
      unawaited(_clearOverrideWhenVisible());
    }
  }

  Future<void> _clearOverrideWhenVisible() async {
    try {
      final visible = await _keyboardVisible();
      if (mounted && visible == true && _ignoreStaleKeyboardInsets) {
        setState(() => _ignoreStaleKeyboardInsets = false);
      }
    } on PlatformException {
      // Keep the override until reliable geometry arrives.
    } on MissingPluginException {
      // Unsupported platforms retain their existing keyboard layout.
    }
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
        resizeToAvoidBottomInset: !_ignoreStaleKeyboardInsets,
        body: Listener(
          behavior: HitTestBehavior.translucent,
          // Raw pointer tracking deliberately observes (but does not win) the
          // gesture arena. Message rows may still claim a left drag for reply,
          // while a right drag anywhere on the timeline reliably opens nav.
          onPointerDown: (event) {
            _keyboardResumeCheck++;
            _keyboardResumeTimer?.cancel();
            _keyboardFocus = null;
            if (_ignoreStaleKeyboardInsets) {
              _keyboardResumeTimer = Timer(
                const Duration(milliseconds: 350),
                () {
                  unawaited(_clearOverrideWhenVisible());
                },
              );
            }
            _pointerStarts[event.pointer] = event.position;
          },
          onPointerMove: (event) {
            final start = _pointerStarts[event.pointer];
            if (start == null || _detailsVisible || room == null) return;
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
            if (_navigationDragProgress == null) {
              FocusManager.instance.primaryFocus?.unfocus();
              _timelineGestureReset?.cancel();
              _suppressTimelineGestures = true;
            }
            final width = MediaQuery.sizeOf(context).width;
            final progress = startedVisible
                ? (1 + delta.dx / width).clamp(0.0, 1.0)
                : (delta.dx / width).clamp(0.0, 1.0);
            setState(() {
              _dragStartedWithNavigation = startedVisible;
              _navigationDragProgress = progress;
            });
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
                child: AnimatedSlide(
                  offset: room == null
                      ? Offset.zero
                      : Offset(0.12 * _navigationProgress, 0),
                  duration: _navigationDragProgress == null
                      ? _duration
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
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
                child: AnimatedSlide(
                  offset: Offset(-1 + _navigationProgress, 0),
                  duration: _navigationDragProgress == null
                      ? _duration
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
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
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewInsets: _ignoreStaleKeyboardInsets
            ? EdgeInsets.zero
            : MediaQuery.viewInsetsOf(context),
      ),
      child: shell,
    );
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
    if (_reportedConversationVisible == visible) return;
    _reportedConversationVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedConversationVisible != visible) return;
      backend.setConversationVisible(visible);
    });
  }
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
