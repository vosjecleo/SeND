import 'dart:typed_data';

enum SessionStatus { starting, signedOut, signingIn, signedIn, failed }

enum EncryptionSetupStatus {
  loading,
  ready,
  needsRecovery,
  needsRepair,
  needsSetup,
  unavailable,
  error,
}

class EncryptionSetupState {
  const EncryptionSetupState({
    required this.status,
    this.keyBackupEnabled = false,
    this.crossSigningEnabled = false,
    this.deviceVerified = false,
    this.message,
  });

  final EncryptionSetupStatus status;
  final bool keyBackupEnabled;
  final bool crossSigningEnabled;
  final bool deviceVerified;
  final String? message;

  bool get needsAttention =>
      status != EncryptionSetupStatus.ready &&
      status != EncryptionSetupStatus.loading;
}

class SpaceSummary {
  const SpaceSummary({required this.id, required this.name, this.avatarBytes});

  final String id;
  final String name;
  final Uint8List? avatarBytes;
}

class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.unreadCount,
    required this.usesChannelIcon,
    this.avatarBytes,
  });

  final String id;
  final String name;
  final String lastMessage;
  final int unreadCount;
  final bool usesChannelIcon;
  final Uint8List? avatarBytes;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestamp,
    required this.pending,
    this.failed = false,
    this.transferStatus,
    this.system = false,
    this.own = false,
    this.canRedact = false,
    this.edited = false,
    this.redacted = false,
    this.reactions = const [],
    this.attachment,
    this.formattedBody,
    this.reply,
    this.avatarBytes,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime timestamp;
  final bool pending;
  final bool failed;
  final String? transferStatus;
  final bool system;
  final bool own;
  final bool canRedact;
  final bool edited;
  final bool redacted;
  final List<ReactionSummary> reactions;
  final ChatAttachment? attachment;
  final String? formattedBody;
  final ReplyPreview? reply;
  final Uint8List? avatarBytes;
}

enum AttachmentKind { image, video, audio, file }

class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.encrypted,
    required this.spoiler,
    this.caption,
    this.hasThumbnail = false,
    this.animated = false,
    this.width,
    this.height,
  });

  final AttachmentKind kind;
  final String name;
  final String mimeType;
  final int? size;
  final bool encrypted;
  final bool spoiler;
  final String? caption;
  final bool hasThumbnail;
  final bool animated;
  final int? width;
  final int? height;
}

class AttachmentDraft {
  const AttachmentDraft({
    required this.bytes,
    required this.name,
    required this.mimeType,
    required this.spoiler,
    this.caption,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
  final bool spoiler;
  final String? caption;
}

class MediaPlaybackSource {
  const MediaPlaybackSource({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class MentionSuggestion {
  const MentionSuggestion({
    required this.userId,
    required this.displayName,
    this.isRoom = false,
  });

  /// Matrix user ID or room ID targeted by the generated matrix.to link.
  final String userId;
  final String displayName;
  final bool isRoom;
}

class ReactionSummary {
  const ReactionSummary({
    required this.key,
    required this.count,
    required this.reactedByMe,
  });

  final String key;
  final int count;
  final bool reactedByMe;
}

class ReplyPreview {
  const ReplyPreview({required this.sender, required this.body});

  final String sender;
  final String body;
}
