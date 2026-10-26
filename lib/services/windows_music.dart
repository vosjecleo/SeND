import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import '../models/user_activity.dart';
import 'activity_candidate.dart';
import 'activity_discovery.dart';
import 'activity_artwork_native.dart';

ActivityKind richPresenceKind(Object? type, String? executable) =>
    type == 2 || (executable != null && isSpotifyApplication(executable))
    ? ActivityKind.music
    : ActivityKind.game;

bool isSpotifyApplication(String id) {
  final name = normalizeActivityPath(id).split('/').last.toLowerCase();
  return name == 'spotify' ||
      name == 'spotify.exe' ||
      name.startsWith('spotifyab.spotifymusic_');
}

ActivityCandidate? windowsMusicFromJson(Object? value, {DateTime? now}) {
  if (value is! Map ||
      value['source'] is! String ||
      value['title'] is! String) {
    return null;
  }
  final source = value['source'] as String,
      title = (value['title'] as String).trim();
  if (source.length > 512 ||
      title.isEmpty ||
      !{'Playing', 'Paused'}.contains(value['state'])) {
    return null;
  }
  if (!isSpotifyApplication(source) && value['type'] != 'Music') return null;
  String text(Object? value, int limit) {
    final s = value is String ? value.trim() : '';
    return s.substring(0, s.length.clamp(0, limit));
  }

  final duration = value['duration'], position = value['position'];
  Uint8List? artwork;
  final encoded = value['artwork'];
  if (encoded is String && encoded.length <= 700000) {
    try {
      artwork = normalizeActivityArtwork(base64Decode(encoded));
    } on FormatException {
      /* Ignore bad art. */
    }
  }
  return ActivityCandidate(
    id: 'music:windows:$source',
    name: text(title, 128),
    kind: ActivityKind.music,
    details: text(value['artist'], 256),
    iconBytes: artwork,
    playback:
        duration is num &&
            duration > 0 &&
            duration <= 86400000 &&
            position is num &&
            position >= 0
        ? ActivityPlayback(
            positionMs: position.round().clamp(0, duration.round()),
            durationMs: duration.round(),
            sampledAt: now ?? DateTime.now(),
            playing: value['state'] == 'Playing',
          )
        : null,
    priority: 100,
  );
}

/// Read the OS media session, never scrape browser/window titles or call a
/// Spotify service. Fixed PowerShell code; no user strings enter the script.
Future<ActivityCandidate?> readWindowsMusic() async {
  if (!Platform.isWindows) return null;
  Process? process;
  Timer? deadline;
  try {
    process = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      windowsMusicScript,
    ]);
    deadline = Timer(const Duration(seconds: 6), () => process?.kill());
    final errors = process.stderr.drain<void>();
    final bytes = <int>[];
    await for (final part in process.stdout) {
      if (bytes.length + part.length > 1024 * 1024) {
        process.kill();
        return null;
      }
      bytes.addAll(part);
    }
    await errors;
    if (await process.exitCode != 0 || bytes.isEmpty) return null;
    return await Isolate.run(
      _DecodeWindowsMusic(utf8.decode(bytes).trim()).call,
    );
  } catch (_) {
    return null;
  } finally {
    deadline?.cancel();
  }
}

class _DecodeWindowsMusic {
  const _DecodeWindowsMusic(this.json);
  final String json;
  ActivityCandidate? call() => windowsMusicFromJson(jsonDecode(json));
}

const windowsMusicScript = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$managerType=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
$propertiesType=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties,Windows.Media.Control,ContentType=WindowsRuntime]
$asTask=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Await-SeND($operation,$type) {
  $task=$asTask.MakeGenericMethod($type).Invoke($null,@($operation))
  if(-not $task.Wait(1500)) { throw 'Media session timeout' }
  return $task.Result
}
$manager=Await-SeND ($managerType::RequestAsync()) $managerType
$sessions=@($manager.GetSessions()) | Select-Object -First 8
$sessions=$sessions | Sort-Object { if($_.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing'){0}else{1} }
foreach($session in $sessions) {
  try {
    $state=$session.GetPlaybackInfo().PlaybackStatus.ToString()
    if($state -ne 'Playing' -and $state -ne 'Paused'){continue}
    $media=Await-SeND ($session.TryGetMediaPropertiesAsync()) $propertiesType
    if(-not $media.Title){continue}
    $source=$session.SourceAppUserModelId
    $type=[string]$media.PlaybackType
    if($source -notmatch '^(Spotify\.exe|SpotifyAB\.SpotifyMusic_[^\s]+)$' -and $type -ne 'Music'){continue}
    $timeline=$session.GetTimelineProperties()
    $art=$null
    try {
      if($media.Thumbnail) {
        $stream=Await-SeND ($media.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType,Windows.Storage.Streams,ContentType=WindowsRuntime])
        try {
          if($stream.Size -gt 0 -and $stream.Size -le 524288) {
            $reader=[Windows.Storage.Streams.DataReader,Windows.Storage.Streams,ContentType=WindowsRuntime]::new($stream)
            try {
              [void](Await-SeND ($reader.LoadAsync([uint32]$stream.Size)) ([uint32]))
              $data=New-Object byte[] ([int]$stream.Size)
              $reader.ReadBytes($data)
              $art=[Convert]::ToBase64String($data)
            } finally {$reader.Dispose()}
          }
        } finally {$stream.Dispose()}
      }
    } catch {}
    @{source=$source;title=$media.Title;artist=$media.Artist;type=$type;state=$state;position=($timeline.Position-$timeline.StartTime).TotalMilliseconds;duration=($timeline.EndTime-$timeline.StartTime).TotalMilliseconds;artwork=$art} | ConvertTo-Json -Compress
    break
  } catch {}
}
''';
