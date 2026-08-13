import 'dart:async';
import 'dart:io';

import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

class MatrixBackend extends ChatBackend {
  Client? _client;
  Timeline? _timeline;
  StreamSubscription<Object?>? _syncSubscription;
  StreamSubscription<Object?>? _loginSubscription;
  SessionStatus _status = SessionStatus.starting;
  String? _error;
  String? _selectedRoomId;
  String? _selectedSpaceId;
  bool _timelineLoading = false;
  final Set<String> _loadedBackupRoomIds = {};
  EncryptionSetupState _encryptionSetup = const EncryptionSetupState(
    status: EncryptionSetupStatus.loading,
  );

  Client get _matrix => _client!;

  @override
  SessionStatus get status => _status;
  @override
  String? get error => _error;
  @override
  String? get userId => _client?.userID;
  @override
  EncryptionSetupState get encryptionSetup => _encryptionSetup;
  @override
  String? get selectedSpaceId => _selectedSpaceId;
  @override
  List<SpaceSummary> get spaces => _joinedRooms
      .where((room) => room.isSpace)
      .map(
        (room) =>
            SpaceSummary(id: room.id, name: room.getLocalizedDisplayname()),
      )
      .toList(growable: false);
  @override
  bool get timelineLoading => _timelineLoading;

  @override
  List<RoomSummary> get rooms {
    final selectedSpaceId = _selectedSpaceId;
    final visible = selectedSpaceId == null
        ? _homeRooms
        : _roomsForSpace(selectedSpaceId);
    return visible.map(_roomSummary).toList(growable: false);
  }

  List<Room> get _joinedRooms =>
      _client?.rooms
          .where((room) => room.membership == Membership.join)
          .toList(growable: false) ??
      const [];

  Set<String> get _allSpaceChildIds => _joinedRooms
      .where((room) => room.isSpace)
      .expand((space) => space.spaceChildren)
      .map((child) => child.roomId)
      .whereType<String>()
      .toSet();

  List<Room> get _homeRooms => _joinedRooms
      .where(
        (room) =>
            !room.isSpace &&
            (room.isDirectChat || !_allSpaceChildIds.contains(room.id)),
      )
      .toList(growable: false);

  List<Room> _roomsForSpace(String spaceId) {
    final space = _client?.getRoomById(spaceId);
    if (space == null || !space.isSpace) return const [];
    final children = space.spaceChildren
        .map((child) => _client?.getRoomById(child.roomId ?? ''))
        .whereType<Room>()
        .where((room) => room.membership == Membership.join && !room.isSpace);
    return children.toList(growable: false);
  }

  @override
  RoomSummary? get selectedRoom {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    return room == null ? null : _roomSummary(room);
  }

  @override
  List<ChatMessage> get messages =>
      _timeline?.events
          .where(
            (event) =>
                event.type == EventTypes.Message ||
                event.type == EventTypes.Encrypted,
          )
          .map(
            (event) => ChatMessage(
              id: event.eventId,
              sender: event.senderFromMemoryOrFallback.calcDisplayname(),
              body: event.type == EventTypes.Encrypted
                  ? 'Unable to decrypt this message'
                  : event.body,
              timestamp: event.originServerTs,
              pending: !event.status.isSent,
            ),
          )
          .toList(growable: false) ??
      const [];

  @override
  Future<void> initialize() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dataDirectory = Directory(p.join(support.path, 'deltiecord'));
      await dataDirectory.create(recursive: true);
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['700', dataDirectory.path]);
      }

      final databasePath = p.join(dataDirectory.path, 'matrix.db');
      late final sqflite.Database database;
      DatabaseFactory? ffiFactory;
      if (Platform.isLinux || Platform.isWindows) {
        sqfliteFfiInit();
        ffiFactory = databaseFactoryFfi;
        database = await ffiFactory.openDatabase(databasePath);
      } else {
        database = await sqflite.openDatabase(databasePath);
      }
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['600', databasePath]);
      }

      final sdkDatabase = await MatrixSdkDatabase.init(
        'deltiecord',
        database: database,
        sqfliteFactory: ffiFactory,
        fileStorageLocation: dataDirectory.uri,
      );
      _client = Client('Deltiecord', database: sdkDatabase);
      _syncSubscription = _matrix.onSync.stream.listen(
        (_) => notifyListeners(),
      );
      _loginSubscription = _matrix.onLoginStateChanged.stream.listen((_) {
        _status = _matrix.isLogged()
            ? SessionStatus.signedIn
            : SessionStatus.signedOut;
        notifyListeners();
      });
      await _matrix.init();
      _status = _matrix.isLogged()
          ? SessionStatus.signedIn
          : SessionStatus.signedOut;
      _error = null;
      if (_matrix.isLogged()) unawaited(refreshEncryptionSetup());
    } catch (exception) {
      _status = SessionStatus.failed;
      _error = _friendlyError(exception);
    }
    notifyListeners();
  }

  @override
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    _status = SessionStatus.signingIn;
    _error = null;
    notifyListeners();
    try {
      await _matrix.checkHomeserver(homeserver);
      await _matrix.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
        initialDeviceDisplayName: 'Deltiecord Desktop',
      );
      _status = SessionStatus.signedIn;
      await refreshEncryptionSetup();
    } catch (exception) {
      _status = SessionStatus.signedOut;
      _error = _friendlyError(exception);
    }
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    _error = null;
    try {
      await _closeTimeline();
      await _matrix.logout();
      _selectedRoomId = null;
      _selectedSpaceId = null;
      _loadedBackupRoomIds.clear();
      _encryptionSetup = const EncryptionSetupState(
        status: EncryptionSetupStatus.loading,
      );
      _status = SessionStatus.signedOut;
    } catch (exception) {
      _error = _friendlyError(exception);
    }
    notifyListeners();
  }

  @override
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  Future<void> refreshEncryptionSetup() async {
    if (_client == null || !_matrix.isLogged()) return;
    _encryptionSetup = const EncryptionSetupState(
      status: EncryptionSetupStatus.loading,
    );
    notifyListeners();
    try {
      final encryption = _matrix.encryption;
      if (encryption == null) {
        _encryptionSetup = const EncryptionSetupState(
          status: EncryptionSetupStatus.unavailable,
          message: 'End-to-end encryption is unavailable on this device.',
        );
      } else {
        final state = await _matrix.getCryptoIdentityState();
        final ownDevice = _matrix
            .userDeviceKeys[_matrix.userID]
            ?.deviceKeys[_matrix.deviceID];
        final deviceVerified = ownDevice?.verified ?? false;
        final hasSecureStorage = encryption.ssss.defaultKeyId != null;
        final status = state.initialized
            ? state.connected && deviceVerified
                  ? EncryptionSetupStatus.ready
                  : EncryptionSetupStatus.needsRecovery
            : hasSecureStorage ||
                  state.keyBackupEnabled ||
                  state.crossSigningEnabled
            ? EncryptionSetupStatus.needsRepair
            : EncryptionSetupStatus.needsSetup;
        _encryptionSetup = EncryptionSetupState(
          status: status,
          keyBackupEnabled: state.keyBackupEnabled,
          crossSigningEnabled: state.crossSigningEnabled,
          deviceVerified: deviceVerified,
        );
      }
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: EncryptionSetupStatus.error,
        message: _friendlyError(exception),
      );
    }
    notifyListeners();
  }

  @override
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase) async {
    final credential = recoveryKeyOrPassphrase.trim();
    if (credential.isEmpty) throw ArgumentError('Enter a recovery key.');
    try {
      final current = await _matrix.getCryptoIdentityState();
      if (current.initialized) {
        if (!current.connected) {
          await _matrix.restoreCryptoIdentity(credential);
        } else {
          await _matrix.encryption!.crossSigning.selfSign(
            keyOrPassphrase: credential,
          );
        }
      } else {
        await _matrix.initCryptoIdentity(
          reuseExistingStorageRecoveryKeyOrPassphrase: credential,
          wipeSecureStorage: false,
          wipeKeyBackup: false,
          wipeCrossSigning: false,
          setupMasterKey: !current.crossSigningEnabled,
          setupSelfSigningKey: !current.crossSigningEnabled,
          setupUserSigningKey: !current.crossSigningEnabled,
          setupOnlineKeyBackup: !current.keyBackupEnabled,
        );
      }
      await refreshEncryptionSetup();
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: _encryptionSetup.status,
        keyBackupEnabled: _encryptionSetup.keyBackupEnabled,
        crossSigningEnabled: _encryptionSetup.crossSigningEnabled,
        deviceVerified: _encryptionSetup.deviceVerified,
        message: _friendlyError(exception),
      );
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<String> createEncryptionSetup() async {
    try {
      final current = await _matrix.getCryptoIdentityState();
      if (current.initialized ||
          _matrix.encryption?.ssss.defaultKeyId != null) {
        throw StateError(
          'Existing encrypted identity data was found. Recover it instead of replacing it.',
        );
      }
      final recoveryKey = await _matrix.initCryptoIdentity(
        keyName: 'Deltiecord recovery key',
        wipeSecureStorage: false,
        wipeKeyBackup: false,
        wipeCrossSigning: false,
      );
      await refreshEncryptionSetup();
      return recoveryKey;
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: _encryptionSetup.status,
        keyBackupEnabled: _encryptionSetup.keyBackupEnabled,
        crossSigningEnabled: _encryptionSetup.crossSigningEnabled,
        deviceVerified: _encryptionSetup.deviceVerified,
        message: _friendlyError(exception),
      );
      notifyListeners();
      rethrow;
    }
  }

  @override
  void selectSpace(String? spaceId) {
    if (_selectedSpaceId == spaceId) return;
    _selectedSpaceId = spaceId;
    _selectedRoomId = null;
    _closeTimeline();
    notifyListeners();
  }

  @override
  Future<void> selectRoom(String roomId) async {
    if (_selectedRoomId == roomId && _timeline != null) return;
    await _closeTimeline();
    _selectedRoomId = roomId;
    _timelineLoading = true;
    _error = null;
    notifyListeners();
    try {
      final room = _matrix.getRoomById(roomId);
      if (room == null) throw StateError('That room is no longer available.');
      await _loadRoomBackupKeys(room);
      _timeline = await room.getTimeline(onUpdate: notifyListeners);
      _timeline!.requestKeys(tryOnlineBackup: true, onlineKeyBackupOnly: false);
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _timelineLoading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> sendMessage(String text) async {
    final value = text.trim();
    if (value.isEmpty || _selectedRoomId == null) return;
    try {
      await _matrix.getRoomById(_selectedRoomId!)!.sendTextEvent(value);
    } catch (exception) {
      _error = _friendlyError(exception);
      notifyListeners();
      rethrow;
    }
  }

  RoomSummary _roomSummary(Room room) => RoomSummary(
    id: room.id,
    name: room.getLocalizedDisplayname(),
    lastMessage: _eventPreview(room.lastEvent),
    unreadCount: room.notificationCount,
  );

  String _eventPreview(Event? event) {
    if (event == null) return 'No messages yet';
    if (event.type == EventTypes.Encrypted) return 'Encrypted message';
    if (event.type != EventTypes.Message) return 'Room activity';
    return event.body;
  }

  Future<void> _loadRoomBackupKeys(Room room) async {
    if (!room.encrypted || _loadedBackupRoomIds.contains(room.id)) return;
    final keyManager = _matrix.encryption?.keyManager;
    if (keyManager == null || !keyManager.enabled) return;
    if (!await keyManager.isCached()) return;
    try {
      await keyManager.loadAllKeysFromRoom(room.id);
      _loadedBackupRoomIds.add(room.id);
    } on MatrixException catch (exception) {
      if (exception.error != MatrixError.M_NOT_FOUND) rethrow;
    }
  }

  Future<void> _closeTimeline() async {
    _timeline?.cancelSubscriptions();
    _timeline = null;
  }

  String _friendlyError(Object exception) {
    final message = exception.toString().replaceFirst('Exception: ', '');
    return message.length > 240 ? '${message.substring(0, 240)}…' : message;
  }

  @override
  void dispose() {
    _timeline?.cancelSubscriptions();
    _syncSubscription?.cancel();
    _loginSubscription?.cancel();
    _client?.dispose();
    super.dispose();
  }
}
