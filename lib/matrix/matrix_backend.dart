import 'dart:async';
import 'dart:io';

import 'package:matrix/matrix.dart' hide RoomSummary;
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

  Client get _matrix => _client!;

  @override
  SessionStatus get status => _status;
  @override
  String? get error => _error;
  @override
  String? get userId => _client?.userID;
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
          .where((event) => event.type == EventTypes.Message)
          .map(
            (event) => ChatMessage(
              id: event.eventId,
              sender: event.senderFromMemoryOrFallback.calcDisplayname(),
              body: event.body,
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
      _timeline = await room.getTimeline(onUpdate: notifyListeners);
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
    lastMessage: room.lastEvent?.body ?? 'No messages yet',
    unreadCount: room.notificationCount,
  );

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
