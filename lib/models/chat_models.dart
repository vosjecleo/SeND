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
    this.reply,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime timestamp;
  final bool pending;
  final ReplyPreview? reply;
}

class ReplyPreview {
  const ReplyPreview({required this.sender, required this.body});

  final String sender;
  final String body;
}
