import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import '../models/chat_models.dart';
import 'recording_storage.dart';

const voiceRecordingLimit = 16 * 1024 * 1024;
const voiceRecordingDuration = Duration(minutes: 10);

abstract interface class VoiceRecorderDriver {
  Stream<double> get levels;
  Future<void> start();
  Future<void> pause();
  Future<void> resume();
  Future<({Uint8List bytes, String path})> stop();
  Future<void> dispose();
}

class PlatformVoiceRecorder implements VoiceRecorderDriver {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  Future<void>? _starting;
  Future<({Uint8List bytes, String path})>? _stopping;
  @override
  Stream<double> get levels => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((level) => pow(10, level.current / 20).toDouble().clamp(0, 1));
  @override
  Future<void> start() => _starting = _start();
  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    final encoder = await _recorder.isEncoderSupported(AudioEncoder.aacLc)
        ? AudioEncoder.aacLc
        : await _recorder.isEncoderSupported(AudioEncoder.opus)
        ? AudioEncoder.opus
        : null;
    if (encoder == null) throw StateError('No supported audio recorder');
    _path = await createRecordingPath(
      encoder == AudioEncoder.aacLc ? 'm4a' : 'ogg',
    );
    await _recorder.start(
      RecordConfig(
        encoder: encoder,
        bitRate: 64000,
        sampleRate: 48000,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  @override
  Future<void> pause() => _recorder.pause();
  @override
  Future<void> resume() => _recorder.resume();
  @override
  Future<({Uint8List bytes, String path})> stop() => _stopping = _stop();
  Future<({Uint8List bytes, String path})> _stop() async {
    final path = await _recorder.stop();
    if (path == null) throw StateError('No recording');
    _path = path;
    return (bytes: await readRecording(path, voiceRecordingLimit), path: path);
  }

  @override
  Future<void> dispose() async {
    // Permission/stop may still be awaiting native IO. Finish them before
    // cleanup so late completion cannot recreate files or microphone tracks.
    try {
      await _starting;
    } catch (_) {}
    try {
      await _stopping;
    } catch (_) {}
    try {
      await _recorder.cancel();
    } finally {
      await _recorder.dispose();
      final path = _path;
      if (path != null && path.isNotEmpty) await deleteRecording(path);
    }
  }
}

/// Inspect the container, not the requested encoder: browsers can choose a
/// different supported container. Never send WebM bytes labelled as MP4/Ogg.
({String mime, String extension}) recordingFormat(Uint8List bytes) {
  bool matches(int offset, List<int> signature) =>
      bytes.length >= offset + signature.length &&
      List.generate(
        signature.length,
        (i) => bytes[offset + i] == signature[i],
      ).every((v) => v);
  if (matches(4, [102, 116, 121, 112])) {
    return (mime: 'audio/mp4', extension: 'm4a');
  }
  if (matches(0, [79, 103, 103, 83])) {
    return (mime: 'audio/ogg', extension: 'ogg');
  }
  if (matches(0, [0x1a, 0x45, 0xdf, 0xa3])) {
    return (mime: 'audio/webm', extension: 'webm');
  }
  if (bytes.length > 2 && bytes[0] == 0xff && (bytes[1] & 0xf6) == 0xf0) {
    return (mime: 'audio/aac', extension: 'aac');
  }
  throw StateError('Unsupported recorded audio container');
}

enum VoiceRecordingState {
  idle,
  starting,
  recording,
  paused,
  stopping,
  ready,
  failed,
}

class VoiceRecordingController extends ChangeNotifier {
  VoiceRecordingController({VoiceRecorderDriver Function()? createDriver})
    : _createDriver = createDriver ?? PlatformVoiceRecorder.new;
  final VoiceRecorderDriver Function() _createDriver;
  VoiceRecorderDriver? _driver;
  StreamSubscription<double>? _levels;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  final List<double> _samples = [];
  int _sampleStride = 1;
  int _sampleCount = 0;
  final List<double> recentLevels = [];
  VoiceRecordingState state = VoiceRecordingState.idle;
  AttachmentDraft? draft;
  String? previewPath;
  String? error;
  bool _disposed = false;
  bool _changing = false;
  Duration get elapsed => _clock.elapsed;
  bool get active =>
      state == VoiceRecordingState.recording ||
      state == VoiceRecordingState.paused;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (state != VoiceRecordingState.idle || _disposed) return;
    state = VoiceRecordingState.starting;
    _notify();
    try {
      final driver = _driver = _createDriver();
      await driver.start();
      if (_disposed) return;
      _clock.start();
      state = VoiceRecordingState.recording;
      _levels = driver.levels.listen(
        (value) {
          if (_disposed || state != VoiceRecordingState.recording) return;
          final sample = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
          recentLevels.add(sample);
          if (recentLevels.length > 80) recentLevels.removeAt(0);
          if (_sampleCount++ % _sampleStride == 0) _samples.add(sample);
          if (_samples.length > 512) {
            final reduced = [
              for (var i = 0; i + 1 < _samples.length; i += 2)
                max(_samples[i], _samples[i + 1]),
            ];
            _samples
              ..clear()
              ..addAll(reduced);
            _sampleStride *= 2;
          }
          _notify();
        },
        onError: (Object _) {
          unawaited(stop());
        },
      );
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (elapsed >= voiceRecordingDuration) unawaited(stop());
        _notify();
      });
    } catch (_) {
      error =
          'Could not record. Check microphone permission and audio input availability.';
      state = VoiceRecordingState.failed;
      await _release();
    }
    _notify();
  }

  Future<void> togglePause() async {
    if (!active || _changing || _disposed) return;
    _changing = true;
    try {
      if (state == VoiceRecordingState.recording) {
        await _driver!.pause();
        if (_disposed || state != VoiceRecordingState.recording) return;
        _clock.stop();
        state = VoiceRecordingState.paused;
      } else {
        await _driver!.resume();
        if (_disposed || state != VoiceRecordingState.paused) return;
        _clock.start();
        state = VoiceRecordingState.recording;
      }
    } catch (_) {
      error = 'Could not change recording state.';
      await stop();
    } finally {
      _changing = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (!active || _disposed) return;
    state = VoiceRecordingState.stopping;
    _clock.stop();
    _timer?.cancel();
    _notify();
    await _levels?.cancel();
    try {
      final audio = await _driver!.stop();
      if (_disposed) return;
      if (audio.bytes.isEmpty || audio.bytes.length > voiceRecordingLimit) {
        throw StateError('Recording too large');
      }
      final format = recordingFormat(audio.bytes);
      previewPath = audio.path;
      draft = AttachmentDraft(
        spoiler: false,
        bytes: audio.bytes,
        name:
            'voice-${DateTime.now().millisecondsSinceEpoch}.${format.extension}',
        mimeType: format.mime,
        voiceMessage: true,
        durationMilliseconds: elapsed.inMilliseconds,
        waveform: [
          for (
            var i = 0;
            i < _samples.length;
            i += max(1, (_samples.length / 256).ceil())
          )
            (_samples[i] * 1024).round(),
        ],
      );
      state = VoiceRecordingState.ready;
    } catch (_) {
      error = 'Could not prepare recording (maximum 16 MiB). Please try again.';
      state = VoiceRecordingState.failed;
      await _release();
    }
    _notify();
  }

  Future<void> _release() async {
    _timer?.cancel();
    _clock.stop();
    await _levels?.cancel();
    final driver = _driver;
    _driver = null;
    try {
      await driver?.dispose();
    } catch (_) {
      /* Cleanup must not hide the original error. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    draft = null;
    unawaited(_release());
    super.dispose();
  }
}
