import 'dart:io';

bool ffmpegToolsAvailable({ProcessResult Function(String, List<String>)? run}) {
  final execute = run ?? (name, args) => Process.runSync(name, args);
  try {
    return execute('ffmpeg', ['-version']).exitCode == 0 &&
        execute('ffprobe', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
