import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/giphy_service.dart';
import 'giphy_dialog.dart';
import 'security_center.dart';
import 'settings_screen.dart';
import 'rich_message.dart';
import 'matrix_html_text.dart';
import 'voice_room_view.dart';

part 'chat_navigation.dart';
part 'conversation_view.dart';
part 'message_composer.dart';
part 'message_row.dart';
part 'message_media.dart';

class ChatShell extends StatefulWidget {
  const ChatShell({required this.backend, super.key});

  final ChatBackend backend;

  @override
  State<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends State<ChatShell> {
  late final QuillController _message;
  final _composerFocus = FocusNode(debugLabel: 'message composer');
  bool _sending = false;
  final List<AttachmentDraft> _pendingAttachments = [];
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
  String? _mentionQuery;
  int? _mentionStart;
  int _mentionSelectionIndex = 0;
  bool _wasTyping = false;
  final GiphyService _giphy = GiphyService();

  @override
  void initState() {
    super.initState();
    _message = QuillController.basic(
      config: QuillControllerConfig(
        // Flutter Quill exposes native clipboard images through this API.
        // ignore: experimental_member_use
        clipboardConfig: QuillClipboardConfig(
          onImagePaste: (bytes) async {
            _queueClipboardImage(bytes);
            // Deltiecord sends pasted images as Matrix attachments instead of
            // inserting a local-only image embed into the text document.
            return null;
          },
          // ignore: experimental_member_use
          onGifPaste: (bytes) async {
            _queueAttachment(
              bytes: bytes,
              name: 'clipboard-${DateTime.now().millisecondsSinceEpoch}.gif',
              mimeType: 'image/gif',
            );
            return null;
          },
        ),
      ),
    );
    _message.addListener(_updateMentionQuery);
  }

  void _updateMentionQuery() {
    final text = _message.document.toPlainText();
    final typing = text.trim().isNotEmpty;
    if (typing != _wasTyping) {
      _wasTyping = typing;
      unawaited(widget.backend.setComposerTyping(typing));
    }
    final cursor = _message.selection.extentOffset.clamp(0, text.length);
    final beforeCursor = text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(beforeCursor);
    final query = match?.group(1);
    final start = match == null ? null : beforeCursor.lastIndexOf('@');
    if (query == _mentionQuery && start == _mentionStart) return;
    setState(() {
      _mentionQuery = query;
      _mentionStart = start;
      _mentionSelectionIndex = 0;
    });
  }

  void _insertMention(String targetId) {
    final start = _mentionStart;
    if (start == null) return;
    MentionSuggestion? suggestion;
    for (final candidate in _mentionSuggestions) {
      if (candidate.matrixId == targetId) {
        suggestion = candidate;
        break;
      }
    }
    if (suggestion == null) return;
    final mentionText = suggestion.isRoom
        ? '#${suggestion.displayName}'
        : suggestion.matrixId;
    final end = _message.selection.extentOffset;
    _message.replaceText(
      start,
      end - start,
      '$mentionText ',
      TextSelection.collapsed(offset: start + mentionText.length + 1),
    );
    _message.formatText(
      start,
      mentionText.length,
      LinkAttribute('https://matrix.to/#/${suggestion.matrixId}'),
    );
    setState(() {
      _mentionQuery = null;
      _mentionStart = null;
    });
    _composerFocus.requestFocus();
  }

  Future<void> _send() async {
    final serialized = serializeRichMessage(_message.document);
    final text = serialized.plainText.trim();
    if ((text.isEmpty && _pendingAttachments.isEmpty) || _sending) return;
    final attachments = List<AttachmentDraft>.from(_pendingAttachments);
    setState(() => _sending = true);
    try {
      if (attachments.isEmpty) {
        await widget.backend.sendMessage(
          text,
          formattedBody: serialized.html,
          replyToMessageId: _replyingTo?.id,
          editMessageId: _editingMessage?.id,
        );
      } else {
        for (var index = 0; index < attachments.length; index++) {
          final attachment = attachments[index];
          await widget.backend.sendAttachment(
            AttachmentDraft(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
              spoiler: attachment.spoiler,
              caption: index == 0 && text.isNotEmpty ? text : null,
            ),
            replyToMessageId: index == 0 ? _replyingTo?.id : null,
          );
        }
      }
      if (mounted) {
        _message.clear();
        setState(() {
          _pendingAttachments.clear();
          _replyingTo = null;
          _editingMessage = null;
        });
      }
    } catch (_) {
      // Leave the document intact so a failed send can be retried.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _replyTo(ChatMessage message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  void _edit(ChatMessage message) {
    _message.document = Document()..insert(0, message.body);
    _message.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: message.body.length),
      ChangeSource.local,
    );
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
    });
    _composerFocus.requestFocus();
  }

  void _cancelComposerAction() {
    setState(() {
      _replyingTo = null;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  Future<void> _attachFile() async {
    if (_sending) return;
    final result = await FilePicker.pickFiles(
      withData: false,
      allowMultiple: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    for (var index = 0; index < result.files.length; index++) {
      final picked = result.files[index];
      final bytes = picked.bytes ?? await result.xFiles[index].readAsBytes();
      if (!mounted) return;
      _queueAttachment(
        bytes: bytes,
        name: picked.name,
        mimeType:
            lookupMimeType(picked.name, headerBytes: bytes) ??
            'application/octet-stream',
      );
    }
  }

  Future<void> _showGifPicker() async {
    final gif = await showDialog<GifSearchResult>(
      context: context,
      builder: (context) => GiphyDialog(service: _giphy),
    );
    if (gif == null || !mounted) {
      _composerFocus.requestFocus();
      return;
    }
    setState(() => _sending = true);
    try {
      final bytes = await _giphy.download(gif);
      await widget.backend.sendAttachment(
        AttachmentDraft(
          bytes: bytes,
          name: 'giphy-${DateTime.now().millisecondsSinceEpoch}.gif',
          mimeType: 'image/gif',
          spoiler: false,
        ),
        replyToMessageId: _replyingTo?.id,
      );
      if (mounted) setState(() => _replyingTo = null);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _composerFocus.requestFocus();
  }

  void _queueClipboardImage(Uint8List bytes) {
    final mimeType = lookupMimeType('', headerBytes: bytes) ?? 'image/png';
    final extension = switch (mimeType) {
      'image/gif' => 'gif',
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
    _queueAttachment(
      bytes: bytes,
      name: 'clipboard-${DateTime.now().millisecondsSinceEpoch}.$extension',
      mimeType: mimeType,
    );
  }

  void _queueAttachment({
    required Uint8List bytes,
    required String name,
    required String mimeType,
  }) async {
    if (!mounted) return;
    setState(
      () => _pendingAttachments.add(
        AttachmentDraft(
          bytes: bytes,
          name: name,
          mimeType: mimeType,
          spoiler: false,
        ),
      ),
    );
    _composerFocus.requestFocus();
  }

  Future<bool> _pasteClipboardImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return false;
    final reader = await clipboard.read();
    if (!reader.canProvide(Formats.png)) return false;
    final completed = Completer<Uint8List?>();
    final progress = reader.getFile(
      Formats.png,
      (file) async => completed.complete(await file.readAll()),
      onError: (_) => completed.complete(null),
    );
    if (progress == null) return false;
    final bytes = await completed.future;
    if (bytes == null || bytes.isEmpty) return false;
    _queueClipboardImage(bytes);
    return true;
  }

  void _removePendingAttachment(int index) {
    setState(() => _pendingAttachments.removeAt(index));
  }

  void _togglePendingSpoiler(int index) {
    final attachment = _pendingAttachments[index];
    setState(() {
      _pendingAttachments[index] = AttachmentDraft(
        bytes: attachment.bytes,
        name: attachment.name,
        mimeType: attachment.mimeType,
        spoiler: !attachment.spoiler,
      );
    });
  }

  @override
  void dispose() {
    _message.removeListener(_updateMentionQuery);
    _message.dispose();
    _composerFocus.dispose();
    _giphy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            showDeltiecordSettings(context, widget.backend),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              if (widget.backend.encryptionSetup.needsAttention)
                _SecurityBanner(backend: widget.backend),
              if (widget.backend.connectionStatus != ConnectionStatus.online)
                _ConnectionBanner(status: widget.backend.connectionStatus),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showSpaceRail = constraints.maxWidth >= 760;
                    final preferredPanel =
                        widget.backend.preferences.roomPanelWidth;
                    final panelWidth = preferredPanel.clamp(
                      220.0,
                      constraints.maxWidth * 0.46,
                    );
                    return Row(
                      children: [
                        if (showSpaceRail) ...[
                          SizedBox(
                            width: 68,
                            child: _SpaceBar(backend: widget.backend),
                          ),
                          const VerticalDivider(width: 1),
                        ],
                        SizedBox(
                          width: panelWidth,
                          child: _RoomPanel(backend: widget.backend),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: widget.backend.selectedRoom == null
                              ? const _EmptyConversation()
                              : widget.backend.selectedRoom!.isVoice
                              ? VoiceRoomView(
                                  backend: widget.backend,
                                  room: widget.backend.selectedRoom!,
                                )
                              : _Conversation(
                                  backend: widget.backend,
                                  controller: _message,
                                  composerFocus: _composerFocus,
                                  sending: _sending,
                                  replyingTo: _replyingTo,
                                  editingMessage: _editingMessage,
                                  onSend: _send,
                                  onReply: _replyTo,
                                  onEdit: _edit,
                                  onCancelComposerAction: _cancelComposerAction,
                                  onAttach: _attachFile,
                                  onGif: _showGifPicker,
                                  onPasteImage: _pasteClipboardImage,
                                  pendingAttachments: _pendingAttachments,
                                  onRemoveAttachment: _removePendingAttachment,
                                  onToggleAttachmentSpoiler:
                                      _togglePendingSpoiler,
                                  mentionSuggestions: _mentionSuggestions,
                                  mentionSelectionIndex: _mentionSelectionIndex,
                                  onMentionSelected: _insertMention,
                                  onMentionSelectionChanged: (index) =>
                                      setState(
                                        () => _mentionSelectionIndex = index,
                                      ),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MentionSuggestion> get _mentionSuggestions {
    final query = _mentionQuery?.toLowerCase();
    if (query == null) return const [];
    return widget.backend.mentionSuggestions
        .where(
          (suggestion) =>
              suggestion.displayName.toLowerCase().contains(query) ||
              suggestion.matrixId.toLowerCase().contains(query),
        )
        .take(6)
        .toList(growable: false);
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (status) {
      ConnectionStatus.connecting => (
        Icons.sync,
        'Connecting to the homeserver…',
      ),
      ConnectionStatus.reconnecting => (
        Icons.sync_problem,
        'Connection interrupted — reconnecting…',
      ),
      ConnectionStatus.offline => (
        Icons.cloud_off_outlined,
        'Offline — messages will send after reconnecting.',
      ),
      ConnectionStatus.online => (Icons.cloud_done_outlined, ''),
    };
    return Material(
      color: const Color(0xff493a1f),
      child: SizedBox(
        height: 34,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
