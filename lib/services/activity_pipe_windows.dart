import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Bounded, local-only byte transport. RPC parsing is shared with Unix sockets.
/// All Win32 calls happen in a worker; shutdown always closes every pipe handle.
class WindowsActivityPipe {
  Isolate? _worker;
  SendPort? _commands;
  ReceivePort? _events;
  final _connections = <int, WindowsActivityConnection>{};

  Future<void> start(void Function(WindowsActivityConnection) accept) async {
    if (_worker != null) return;
    final ready = Completer<void>();
    final events = _events = ReceivePort();
    events.listen((dynamic event) {
      if (event is SendPort) {
        _commands = event;
        if (!ready.isCompleted) ready.complete();
      } else if (event is String) {
        if (!ready.isCompleted) ready.completeError(StateError(event));
      } else if (event is List) {
        final id = event[1] as int;
        if (event[0] == 'open') {
          final connection = WindowsActivityConnection(
            id,
            event[2] as String?,
            _commands!,
          );
          _connections[id] = connection;
          accept(connection);
        } else if (event[0] == 'data') {
          _connections[id]?._input.add(event[2] as Uint8List);
        } else if (event[0] == 'close') {
          _connections.remove(id)?._input.close();
        }
      }
    });
    _worker = await Isolate.spawn(_runPipes, events.sendPort);
    try {
      await ready.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> close() async {
    final worker = _worker;
    if (worker == null) return;
    _worker = null;
    final stopped = ReceivePort();
    worker.addOnExitListener(stopped.sendPort);
    _commands?.send('stop');
    try {
      await stopped.first.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      worker.kill(priority: Isolate.immediate);
    }
    stopped.close();
    _commands = null;
    _events?.close();
    for (final connection in _connections.values) {
      unawaited(connection._input.close());
    }
    _connections.clear();
  }
}

class WindowsActivityConnection {
  WindowsActivityConnection(this.id, this.executable, this._commands);
  final int id;
  final String? executable;
  final SendPort _commands;
  final _input = StreamController<List<int>>();
  Stream<List<int>> get input => _input.stream;
  void add(List<int> bytes) =>
      _commands.send(['write', id, Uint8List.fromList(bytes)]);
  void destroy() => _commands.send(['close', id]);
}

String? windowsProcessPath(int pid) => using((arena) {
  final process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == 0) return null;
  try {
    final length = arena<Uint32>()..value = 32768;
    final path = arena<Uint16>(32768).cast<Utf16>();
    return QueryFullProcessImageName(process, 0, path, length) == 0
        ? null
        : path.toDartString();
  } finally {
    CloseHandle(process);
  }
});

Future<void> _runPipes(SendPort events) async {
  final commands = ReceivePort();
  final handles = <int, int>{};
  final connected = <int>{};
  var stopped = false;
  var nextId = 0;
  final convert = DynamicLibrary.open('advapi32.dll')
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Uint32>,
        )
      >('ConvertStringSecurityDescriptorToSecurityDescriptorW');
  final descriptor = calloc<Pointer<Void>>();
  final security = calloc<SECURITY_ATTRIBUTES>();
  final name = r'\\.\pipe\discord-ipc-0'.toNativeUtf16();
  final sddl = 'D:P(A;;GA;;;SY)(A;;GA;;;OW)'.toNativeUtf16();
  int open({bool first = false}) {
    final handle = CreateNamedPipe(
      name,
      PIPE_ACCESS_DUPLEX | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0),
      PIPE_TYPE_BYTE |
          PIPE_READMODE_BYTE |
          PIPE_NOWAIT |
          PIPE_REJECT_REMOTE_CLIENTS,
      8,
      65536,
      65536,
      0,
      security,
    );
    if (handle == INVALID_HANDLE_VALUE) return -1;
    final id = nextId++;
    handles[id] = handle;
    return id;
  }

  void close(int id) {
    final handle = handles[id];
    if (handle == null) return;
    // Never drop the final instance between polling iterations. Otherwise a
    // short-lived client / transient pipe error opens a window in which another
    // process can acquire FILE_FLAG_FIRST_PIPE_INSTANCE and steal ownership.
    if (!stopped && handles.length == 1 && open() < 0) {
      throw StateError('Windows IPC could not retain its listening pipe.');
    }
    handles.remove(id);
    DisconnectNamedPipe(handle);
    CloseHandle(handle);
    if (connected.remove(id)) events.send(['close', id]);
  }

  try {
    if (convert(sddl, 1, descriptor, nullptr) == 0) {
      throw StateError('Could not secure the Discord compatibility pipe.');
    }
    security.ref
      ..nLength = sizeOf<SECURITY_ATTRIBUTES>()
      ..lpSecurityDescriptor = descriptor.value
      ..bInheritHandle = FALSE;
    if (open(first: true) < 0) {
      throw StateError(
        'Discord IPC is already in use or unavailable. Close Discord before enabling compatibility.',
      );
    }
    commands.listen((dynamic command) {
      if (command == 'stop') {
        stopped = true;
        return;
      }
      if (command is! List) return;
      final id = command[1] as int;
      final handle = handles[id];
      if (handle == null) return;
      if (command[0] == 'close') {
        close(id);
        return;
      }
      final bytes = command[2] as Uint8List;
      if (bytes.length > 65536) {
        close(id);
        return;
      }
      using((arena) {
        final buffer = arena<Uint8>(bytes.length)
          ..asTypedList(bytes.length).setAll(0, bytes);
        final written = arena<Uint32>();
        if (WriteFile(handle, buffer, bytes.length, written, nullptr) == 0 ||
            written.value != bytes.length) {
          close(id);
        }
      });
    });
    events.send(commands.sendPort);
    while (!stopped) {
      for (final entry in handles.entries.toList()) {
        final id = entry.key, handle = entry.value;
        if (!connected.contains(id)) {
          final ok = ConnectNamedPipe(handle, nullptr);
          final error = ok == 0 ? GetLastError() : 0;
          if (error == ERROR_PIPE_LISTENING || error == ERROR_NO_DATA) continue;
          if (ok == 0 && error != ERROR_PIPE_CONNECTED) {
            close(id);
            continue;
          }
          final peer = using((arena) {
            final pid = arena<Uint32>();
            return GetNamedPipeClientProcessId(handle, pid) != 0
                ? pid.value
                : null;
          });
          // PIPE_NOWAIT can report a successful transition into listening
          // state before a client exists. Do not close that listening handle.
          if (peer == null) continue;
          connected.add(id);
          final executable = windowsProcessPath(peer);
          events.send(['open', id, executable]);
        }
        using((arena) {
          final available = arena<Uint32>();
          if (PeekNamedPipe(handle, nullptr, 0, nullptr, available, nullptr) ==
              0) {
            close(id);
            return;
          }
          if (available.value == 0) return;
          final size = available.value.clamp(0, 65536);
          final buffer = arena<Uint8>(size), read = arena<Uint32>();
          if (ReadFile(handle, buffer, size, read, nullptr) == 0) {
            close(id);
            return;
          }
          events.send([
            'data',
            id,
            Uint8List.fromList(buffer.asTypedList(read.value)),
          ]);
        });
      }
      if (handles.length < 8 && handles.keys.every(connected.contains)) {
        open(first: handles.isEmpty);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } catch (error) {
    events.send(
      error is StateError
          ? error.message.toString()
          : 'Windows IPC could not start.',
    );
  } finally {
    stopped = true;
    for (final id in handles.keys.toList()) {
      close(id);
    }
    commands.close();
    if (descriptor.value != nullptr) LocalFree(descriptor.value);
    calloc.free(descriptor);
    calloc.free(security);
    calloc.free(name);
    calloc.free(sddl);
  }
}
