import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/activity_pipe_windows.dart';

// A real Windows named-pipe round trip, run in Windows CI (not emulated on Linux).
void main() {
  test(
    'Windows IPC accepts a local connection and does not steal a live pipe',
    () async {
      final pipe = WindowsActivityPipe(), other = WindowsActivityPipe();
      try {
        await pipe.start((connection) {
          connection.input.listen(connection.add);
        });
        // Exercise both initial ownership and the gap after a client closes.
        for (var attempt = 0; attempt < 3; attempt++) {
          await expectLater(other.start((_) {}), throwsStateError);
          final result = await Isolate.run(_roundTrip);
          expect(result, [1, 2, 3, 4]);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      } finally {
        await other.close();
        await pipe.close();
      }
      // Handle cleanup must permit binding again without killing a process.
      await pipe.start((connection) => connection.input.listen((_) {}));
      await pipe.close();
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<List<int>> _roundTrip() async {
  final name = r'\\.\pipe\discord-ipc-0'.toNativeUtf16();
  var handle = INVALID_HANDLE_VALUE;
  try {
    handle = CreateFile(
      name,
      GENERIC_READ | GENERIC_WRITE,
      0,
      nullptr,
      OPEN_EXISTING,
      0,
      NULL,
    );
    if (handle == INVALID_HANDLE_VALUE) {
      throw StateError('Could not connect: ${GetLastError()}');
    }
    using((arena) {
      final mode = arena<Uint32>()..value = PIPE_NOWAIT;
      if (SetNamedPipeHandleState(handle, mode, nullptr, nullptr) == 0) {
        throw StateError('Could not set pipe mode');
      }
      final buffer = arena<Uint8>(4)..asTypedList(4).setAll(0, [1, 2, 3, 4]);
      final written = arena<Uint32>();
      if (WriteFile(handle, buffer, 4, written, nullptr) == 0) {
        throw StateError('Could not write');
      }
    });
    final result = <int>[];
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (result.length < 4 && DateTime.now().isBefore(deadline)) {
      using((arena) {
        final buffer = arena<Uint8>(4), read = arena<Uint32>();
        if (ReadFile(handle, buffer, 4, read, nullptr) != 0) {
          result.addAll(buffer.asTypedList(read.value));
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return result;
  } finally {
    if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
    calloc.free(name);
  }
}
