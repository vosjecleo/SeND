import 'dart:typed_data';

enum SessionStatus { starting, signedOut, signingIn, signedIn, failed }

enum ConnectionStatus { connecting, online, reconnecting, offline }

enum InterfaceDensity { compact, cozy }

enum SettingsShortcut { controlComma, controlShiftS, controlAltS }

class AppPreferences {
  const AppPreferences({
    this.density = InterfaceDensity.compact,
    this.fontScale = 1,
    this.roomPanelWidth = 280,
    this.reducedMotion = false,
    this.highContrast = false,
    this.autoplayGifs = true,
    this.notificationsEnabled = true,
    this.notificationSound = true,
    this.sendReadReceipts = true,
    this.sendTypingNotifications = true,
    this.sharePresence = true,
    this.accentColor = 0xff6975d9,
    this.fontFamily = 'System',
    this.showNativeTitleBar = true,
    this.rememberWindowState = true,
    this.settingsShortcut = SettingsShortcut.controlComma,
    this.sendWithCtrlEnter = false,
  });

  final InterfaceDensity density;
  final double fontScale;
  final double roomPanelWidth;
  final bool reducedMotion;
  final bool highContrast;
  final bool autoplayGifs;
  final bool notificationsEnabled;
  final bool notificationSound;
  final bool sendReadReceipts;
  final bool sendTypingNotifications;
  final bool sharePresence;
  final int accentColor;
  final String fontFamily;
  final bool showNativeTitleBar;
  final bool rememberWindowState;
  final SettingsShortcut settingsShortcut;
  final bool sendWithCtrlEnter;

  AppPreferences copyWith({
    InterfaceDensity? density,
    double? fontScale,
    double? roomPanelWidth,
    bool? reducedMotion,
    bool? highContrast,
    bool? autoplayGifs,
    bool? notificationsEnabled,
    bool? notificationSound,
    bool? sendReadReceipts,
    bool? sendTypingNotifications,
    bool? sharePresence,
    int? accentColor,
    String? fontFamily,
    bool? showNativeTitleBar,
    bool? rememberWindowState,
    SettingsShortcut? settingsShortcut,
    bool? sendWithCtrlEnter,
  }) => AppPreferences(
    density: density ?? this.density,
    fontScale: fontScale ?? this.fontScale,
    roomPanelWidth: roomPanelWidth ?? this.roomPanelWidth,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    highContrast: highContrast ?? this.highContrast,
    autoplayGifs: autoplayGifs ?? this.autoplayGifs,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    notificationSound: notificationSound ?? this.notificationSound,
    sendReadReceipts: sendReadReceipts ?? this.sendReadReceipts,
    sendTypingNotifications:
        sendTypingNotifications ?? this.sendTypingNotifications,
    sharePresence: sharePresence ?? this.sharePresence,
    accentColor: accentColor ?? this.accentColor,
    fontFamily: fontFamily ?? this.fontFamily,
    showNativeTitleBar: showNativeTitleBar ?? this.showNativeTitleBar,
    rememberWindowState: rememberWindowState ?? this.rememberWindowState,
    settingsShortcut: settingsShortcut ?? this.settingsShortcut,
    sendWithCtrlEnter: sendWithCtrlEnter ?? this.sendWithCtrlEnter,
  );
}

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

enum RoomPresentation { text, voice }

enum VoiceConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class AudioInputSummary {
  const AudioInputSummary({required this.id, required this.label});

  final String id;
  final String label;
}

class DeviceSessionSummary {
  const DeviceSessionSummary({
    required this.id,
    required this.displayName,
    required this.current,
    this.lastSeenAt,
    this.lastSeenIp,
  });

  final String id;
  final String displayName;
  final bool current;
  final DateTime? lastSeenAt;
  final String? lastSeenIp;
}

enum UserPresence { online, away, offline }

class RoomMemberSummary {
  const RoomMemberSummary({
    required this.userId,
    required this.displayName,
    this.avatarBytes,
    this.presence = UserPresence.offline,
    this.powerLevel = 0,
    this.canChangePowerLevel = false,
    this.maxAssignablePowerLevel = 0,
  });

  final String userId;
  final String displayName;
  final Uint8List? avatarBytes;
  final UserPresence presence;
  final int powerLevel;
  final bool canChangePowerLevel;
  final int maxAssignablePowerLevel;
}

class VoiceParticipantSummary {
  const VoiceParticipantSummary({
    required this.userId,
    required this.displayName,
    this.avatarBytes,
    this.speaking = false,
  });

  final String userId;
  final String displayName;
  final Uint8List? avatarBytes;
  final bool speaking;
}

class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.unreadCount,
    required this.usesChannelIcon,
    this.presentation = RoomPresentation.text,
    this.voiceParticipants = const [],
    this.avatarBytes,
    this.topic = '',
  });

  final String id;
  final String name;
  final String lastMessage;
  final int unreadCount;
  final bool usesChannelIcon;
  final RoomPresentation presentation;
  final List<VoiceParticipantSummary> voiceParticipants;
  final Uint8List? avatarBytes;
  final String topic;

  bool get isVoice => presentation == RoomPresentation.voice;
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
    this.linkPreview,
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
  final LinkPreview? linkPreview;
}

class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.siteName,
    this.imageBytes,
    this.videoUrl,
    this.width,
    this.height,
  });

  final Uri url;
  final String? title;
  final String? description;
  final String? siteName;
  final Uint8List? imageBytes;
  final Uri? videoUrl;
  final int? width;
  final int? height;
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
    required this.matrixId,
    required this.displayName,
    this.isRoom = false,
  });

  /// Matrix user ID or room ID targeted by the generated matrix.to link.
  final String matrixId;
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
