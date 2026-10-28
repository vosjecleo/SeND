import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'support/ffmpeg_tools.dart';

void main() {
  test('missing ffmpeg is reported as unavailable rather than thrown', () {
    expect(
      ffmpegToolsAvailable(
        run: (name, args) => throw ProcessException(name, args),
      ),
      false,
    );
  });
  test('ffprobe is required as well as ffmpeg', () {
    expect(
      ffmpegToolsAvailable(
        run: (name, args) {
          if (name == 'ffprobe') throw ProcessException(name, args);
          return ProcessResult(1, 0, '', '');
        },
      ),
      false,
    );
  });
  test('both working tools enable codec integration tests', () {
    final calls = <String>[];
    expect(
      ffmpegToolsAvailable(
        run: (name, _) {
          calls.add(name);
          return ProcessResult(1, 0, '', '');
        },
      ),
      true,
    );
    expect(calls, ['ffmpeg', 'ffprobe']);
  });
}
