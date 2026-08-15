import 'dart:typed_data';

import 'package:webrtc_interface/webrtc_interface.dart';

enum SessionStatus { starting, signedOut, signingIn, signedIn, failed }

enum ConnectionStatus { connecting, online, reconnecting, offline }

enum InterfaceDensity { compact, cozy }

enum AppShortcutAction {
  openSettings,
  toggleMicrophone,
  toggleDeafen,
  disconnectVoice,
  openGifPicker,
  openEmojiPicker,
  openFilePicker,
  focusComposer,
  searchRoom,
  toggleMembers,
}

const defaultShortcutBindings = <AppShortcutAction, String>{
  AppShortcutAction.openSettings: 'control+comma',
  AppShortcutAction.toggleMicrophone: 'control+shift+m',
  AppShortcutAction.toggleDeafen: 'control+shift+d',
  AppShortcutAction.disconnectVoice: 'control+shift+backslash',
  AppShortcutAction.openGifPicker: 'control+g',
  AppShortcutAction.openEmojiPicker: 'control+e',
  AppShortcutAction.openFilePicker: 'control+u',
  AppShortcutAction.focusComposer: 'control+l',
  AppShortcutAction.searchRoom: 'control+f',
  AppShortcutAction.toggleMembers: 'control+shift+u',
};

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
    this.shortcutBindings = defaultShortcutBindings,
    this.sendWithCtrlEnter = false,
    this.readReceiptMemberThreshold = 10,
    this.timelineChunkSize = 30,
    this.timelineChunkCap = 3,
    this.preferredAudioInputId = '',
    this.preferredAudioOutputId = '',
    this.preferredCameraId = '',
    this.participantVolumes = const {},
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
  final Map<AppShortcutAction, String> shortcutBindings;
  final bool sendWithCtrlEnter;
  final int readReceiptMemberThreshold;
  final int timelineChunkSize;
  final int timelineChunkCap;
  final String preferredAudioInputId;
  final String preferredAudioOutputId;
  final String preferredCameraId;
  final Map<String, double> participantVolumes;

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
    Map<AppShortcutAction, String>? shortcutBindings,
    bool? sendWithCtrlEnter,
    int? readReceiptMemberThreshold,
    int? timelineChunkSize,
    int? timelineChunkCap,
    String? preferredAudioInputId,
    String? preferredAudioOutputId,
    String? preferredCameraId,
    Map<String, double>? participantVolumes,
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
    shortcutBindings: shortcutBindings ?? this.shortcutBindings,
    sendWithCtrlEnter: sendWithCtrlEnter ?? this.sendWithCtrlEnter,
    readReceiptMemberThreshold:
        readReceiptMemberThreshold ?? this.readReceiptMemberThreshold,
    timelineChunkSize: timelineChunkSize ?? this.timelineChunkSize,
    timelineChunkCap: timelineChunkCap ?? this.timelineChunkCap,
    preferredAudioInputId: preferredAudioInputId ?? this.preferredAudioInputId,
    preferredAudioOutputId:
        preferredAudioOutputId ?? this.preferredAudioOutputId,
    preferredCameraId: preferredCameraId ?? this.preferredCameraId,
    participantVolumes: participantVolumes ?? this.participantVolumes,
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

class RtcDeviceSummary {
  const RtcDeviceSummary({required this.id, required this.label});

  final String id;
  final String label;
}

class RtcMediaStreamSummary {
  const RtcMediaStreamSummary({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.stream,
    required this.local,
    required this.screenShare,
    required this.videoMuted,
  });

  final String id;
  final String userId;
  final String displayName;
  final MediaStream stream;
  final bool local;
  final bool screenShare;
  final bool videoMuted;
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

class UserProfileSummary {
  const UserProfileSummary({
    required this.userId,
    required this.displayName,
    this.avatarBytes,
    this.bannerBytes,
    this.presence = UserPresence.offline,
    this.bio,
    this.pronouns,
    this.timezone,
    this.extensibleFieldsSupported = true,
    this.blocked = false,
  });

  final String userId;
  final String displayName;
  final Uint8List? avatarBytes;
  final Uint8List? bannerBytes;
  final UserPresence presence;
  final String? bio;
  final String? pronouns;
  final String? timezone;
  final bool extensibleFieldsSupported;
  final bool blocked;
}

class VoiceParticipantSummary {
  const VoiceParticipantSummary({
    required this.userId,
    required this.displayName,
    this.avatarBytes,
    this.speaking = false,
    this.localVolume = 1,
    this.locallyMuted = false,
  });

  final String userId;
  final String displayName;
  final Uint8List? avatarBytes;
  final bool speaking;
  final double localVolume;
  final bool locallyMuted;
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
    this.readBy = const [],
    this.senderId,
    this.blocked = false,
    this.queued = false,
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
  final List<ReceiptReaderSummary> readBy;
  final String? senderId;
  final bool blocked;
  final bool queued;
}

class ReceiptReaderSummary {
  const ReceiptReaderSummary({required this.userId, required this.displayName});

  final String userId;
  final String displayName;
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
  const ReplyPreview({
    required this.eventId,
    required this.sender,
    required this.body,
  });

  final String eventId;
  final String sender;
  final String body;
}
