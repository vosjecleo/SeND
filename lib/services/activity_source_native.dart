import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/user_activity.dart';
import 'activity_candidate.dart';
import 'activity_artwork_native.dart';
import 'activity_discovery.dart';
import 'activity_ipc_native.dart';

/// Local-only discovery. Never executes desktop entries or launcher commands.
class DesktopActivitySource {
  DesktopActivitySource({this.ipcDirectory});

  /// Test overrides must still reside in the user's private runtime directory.
  final String? ipcDirectory;
  bool get supported => Platform.isLinux || Platform.isWindows;
  String? warning;
  ServerSocket? _server;
  String? _socketPath;
  String? _socketIdentity;
  final Set<Socket> _clients = {};
  final Map<Socket, ActivityCandidate> _rpc = {};
  List<ActivityCandidate> _catalogue = [];
  DateTime? _catalogueAt;
  bool _disposed = false;
  final _artwork = ActivityArtworkCache();

  Future<List<ActivityCandidate>> scan(ActivitySettings settings) async {
    if (_disposed || !supported || !settings.detect) {
      await _closeRpc();
      return [];
    }
    if (settings.rpc && Platform.isLinux) {
      await _listenRpc();
    } else {
      await _closeRpc();
      warning = settings.rpc && Platform.isWindows
          ? 'Discord IPC capture is not available on Windows in this preview. Local program detection still works.'
          : null;
    }
    if (_catalogueAt == null ||
        DateTime.now().difference(_catalogueAt!) > const Duration(minutes: 5)) {
      _catalogue = await Isolate.run(loadLocalActivityCatalogue);
      _catalogueAt = DateTime.now();
    }
    final catalogue = _catalogue;
    final rules = settings.rules;
    // A closure created in this method can capture the same context as the RPC
    // filters below, including this source's non-sendable live ServerSocket.
    final detected = await Isolate.run(
      ActivityProcessScan(catalogue, rules).call,
    );
    final music = Platform.isLinux ? await _linuxMusic(_artwork) : null;
    return [
      // Prefer the player's richer music record (artwork, pause and position)
      // over music-only RPC. Game RPC retains priority over background music.
      for (final activity in _rpc.values.where(
        (rpc) => !preferPlayerMusic(rpc, music),
      ))
        ActivityCandidate(
          id: activity.id,
          name:
              detected.where((e) => e.id == activity.id).firstOrNull?.name ??
              activity.name,
          kind: activity.kind,
          details: activity.details,
          iconBytes: detected
              .where((e) => e.id == activity.id)
              .firstOrNull
              ?.iconBytes,
        ),
      ?music,
      ...detected.where((e) => !_rpc.values.any((rpc) => rpc.id == e.id)),
    ];
  }

  Future<void> _listenRpc() async {
    if (_server != null) return;
    final runtime = ipcDirectory ?? Platform.environment['XDG_RUNTIME_DIR'];
    if (runtime == null || !runtime.startsWith('/run/user/')) {
      warning = 'Discord compatibility needs a private XDG runtime directory.';
      return;
    }
    final socketPath = '$runtime/discord-ipc-0';
    if (!await prepareActivitySocket(socketPath, runtime)) {
      warning =
          'Discord IPC is already in use. Close Discord and retry compatibility capture.';
      return;
    }
    try {
      _server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      _socketPath = socketPath;
      await Process.run('chmod', ['600', socketPath]);
      _socketIdentity = await activitySocketIdentity(socketPath);
      warning = null;
      _server!.listen(_accept);
    } catch (_) {
      warning = 'Could not open the local Discord compatibility socket.';
      await _closeRpc();
    }
  }

  void _accept(Socket socket) {
    if (_clients.length >= 8 || _disposed) {
      socket.destroy();
      return;
    }
    _clients.add(socket);
    var buffer = <int>[];
    String? clientId;
    Timer? timeout;
    void finish() {
      timeout?.cancel();
      _clients.remove(socket);
      _rpc.remove(socket);
      socket.destroy();
    }

    void send(int opcode, Object data) {
      final payload = utf8.encode(jsonEncode(data));
      final header = ByteData(8)
        ..setUint32(0, opcode, Endian.little)
        ..setUint32(4, payload.length, Endian.little);
      socket.add([...header.buffer.asUint8List(), ...payload]);
    }

    timeout = Timer(const Duration(seconds: 10), finish);
    socket.listen(
      (bytes) {
        if (buffer.length + bytes.length > 128 * 1024) {
          finish();
          return;
        }
        buffer.addAll(bytes);
        try {
          while (buffer.length >= 8) {
            final header = ByteData.sublistView(
              Uint8List.fromList(buffer.sublist(0, 8)),
            );
            final opcode = header.getUint32(0, Endian.little);
            final size = header.getUint32(4, Endian.little);
            if (size > 64 * 1024) {
              finish();
              return;
            }
            if (buffer.length < size + 8) break;
            final message = jsonDecode(
              utf8.decode(buffer.sublist(8, size + 8)),
            );
            buffer = buffer.sublist(size + 8);
            if (message is! Map) {
              finish();
              return;
            }
            if (opcode == 0) {
              final id = message['client_id'];
              if (message['v'] != 1 ||
                  id is! String ||
                  !RegExp(r'^\d{1,24}$').hasMatch(id)) {
                finish();
                return;
              }
              clientId = id;
              timeout?.cancel();
              send(1, {
                'cmd': 'DISPATCH',
                'evt': 'READY',
                'data': {
                  'v': 1,
                  'config': {'api_endpoint': '', 'environment': 'production'},
                  'user': {
                    'id': '0',
                    'username': 'SeND',
                    'discriminator': '0000',
                    'avatar': null,
                  },
                },
              });
            } else if (opcode == 3) {
              send(4, message);
            } else if (opcode == 2) {
              finish();
            } else if (opcode == 1 && clientId != null) {
              final args = message['args'];
              if (message['cmd'] == 'SET_ACTIVITY' && args is Map) {
                final activity = args['activity'];
                if (activity == null) {
                  _rpc.remove(socket);
                } else if (activity is Map) {
                  final pid = args['pid'];
                  String? exe;
                  if (pid is int && pid > 0) {
                    try {
                      exe = Link('/proc/$pid/exe').resolveSymbolicLinksSync();
                    } catch (_) {}
                  }
                  _rpc[socket] = ActivityCandidate(
                    id: exe ?? 'rpc:$clientId',
                    name: exe?.split('/').last ?? 'Application $clientId',
                    kind: activity['type'] == 2
                        ? ActivityKind.music
                        : ActivityKind.game,
                    details: _boundedText(
                      [
                        activity['details'],
                        activity['state'],
                      ].whereType<String>().join(' — '),
                      256,
                    ),
                  );
                }
                // No join secrets, arbitrary URLs, Discord tokens or RPC controls.
                send(1, {
                  'cmd': 'SET_ACTIVITY',
                  'nonce': message['nonce'],
                  'data': null,
                });
              } else {
                send(1, {
                  'cmd': message['cmd'],
                  'nonce': message['nonce'],
                  'evt': 'ERROR',
                  'data': {
                    'code': 4000,
                    'message': 'Only activity presentation is supported',
                  },
                });
              }
            }
          }
        } catch (_) {
          finish();
        }
      },
      onDone: finish,
      onError: (_) => finish(),
    );
  }

  Future<void> _closeRpc() async {
    for (final socket in _clients.toList()) {
      socket.destroy();
    }
    _clients.clear();
    _rpc.clear();
    await _server?.close();
    _server = null;
    final path = _socketPath;
    final identity = _socketIdentity;
    _socketPath = null;
    _socketIdentity = null;
    if (path != null && identity != null) {
      try {
        if (await activitySocketIdentity(path) == identity) {
          await File(path).delete();
        }
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _closeRpc();
  }
}

String _boundedText(String value, int maximum) => value
    .replaceAll(RegExp(r'[\x00-\x1f]'), ' ')
    .substring(0, value.length.clamp(0, maximum));

Uint8List? _icon(String? path) {
  if (path == null ||
      !path.startsWith('/') ||
      !path.toLowerCase().endsWith('.png')) {
    return null;
  }
  try {
    final file = File(path);
    if (file.lengthSync() > 1024 * 1024) return null;
    final bytes = file.readAsBytesSync();
    if (bytes.length < 24) return null;
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(16) > 2048 || header.getUint32(20) > 2048) return null;
    final decoded = img.decodePng(bytes);
    if (decoded == null || decoded.width > 2048 || decoded.height > 2048) {
      return null;
    }
    return Uint8List.fromList(
      img.encodePng(
        img.copyResize(decoded, width: 96, height: 96, maintainAspect: true),
      ),
    );
  } catch (_) {
    return null;
  }
}

List<ActivityCandidate> loadLocalActivityCatalogue() {
  if (!Platform.isLinux) return [];
  final homeDir = Platform.environment['HOME'] ?? '';
  final data = Platform.environment['XDG_DATA_HOME'] ?? '$homeDir/.local/share';
  final roots = [
    data,
    ...(Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
        .split(':'),
  ];
  final entries = <ActivityCandidate>[];
  final steamShortcuts = <String, ActivityCandidate>{};
  for (final root in roots) {
    final directory = Directory('$root/applications');
    if (!directory.existsSync()) continue;
    for (final file
        in directory
            .listSync(followLinks: false)
            .whereType<File>()
            .take(3000)) {
      if (!file.path.endsWith('.desktop') || file.lengthSync() > 128 * 1024) {
        continue;
      }
      try {
        final fields = <String, String>{};
        var section = false;
        for (final line in file.readAsLinesSync()) {
          if (line.startsWith('[')) {
            section = line == '[Desktop Entry]';
            continue;
          }
          final at = line.indexOf('=');
          if (section && at > 0) {
            fields[line.substring(0, at)] = line.substring(at + 1);
          }
        }
        final exec = fields['Exec'] ?? '';
        final binary = RegExp(r'^\s*(?:"([^"]+)"|(\S+))').firstMatch(exec);
        if (binary == null ||
            fields['Name'] == null ||
            fields['Hidden'] == 'true') {
          continue;
        }
        final executable = binary.group(1) ?? binary.group(2)!;
        if (['env', 'sh', 'bash'].contains(executable)) continue;
        final categories = (fields['Categories'] ?? '').split(';');
        String? iconPath = fields['Icon'];
        if (iconPath != null && !iconPath.startsWith('/')) {
          iconPath = [
            for (final r in roots)
              for (final size in ['128x128', '96x96', '64x64', '48x48'])
                '$r/icons/hicolor/$size/apps/$iconPath.png',
            '/usr/share/pixmaps/$iconPath.png',
          ].where((p) => File(p).existsSync()).firstOrNull;
        }
        final entry = ActivityCandidate(
          id: executable,
          name: fields['Name']!,
          kind: categories.contains('Game') ? ActivityKind.game : null,
          iconBytes: _icon(iconPath),
        );
        final steamId = steamShortcutAppId(exec);
        if (steamId != null) {
          steamShortcuts[steamId] = entry;
        } else {
          entries.add(entry);
        }
      } catch (_) {}
    }
  }
  // Join categorized shortcuts to the actual installation, never to Steam's
  // launcher process. Installed software is not proof of running activity.
  for (final steam in [
    '$homeDir/.local/share/Steam',
    '$homeDir/.steam/steam',
  ]) {
    final libraries = <String>{steam};
    try {
      final vdf = File('$steam/steamapps/libraryfolders.vdf');
      if (vdf.lengthSync() < 1024 * 1024) {
        libraries.addAll(
          RegExp(
            r'"path"\s+"([^"]+)"',
          ).allMatches(vdf.readAsStringSync()).map((m) => m.group(1)!),
        );
      }
    } catch (_) {}
    for (final library in libraries) {
      final dir = Directory('$library/steamapps');
      if (!dir.existsSync()) continue;
      for (final manifest
          in dir
              .listSync(followLinks: false)
              .whereType<File>()
              .where((f) => RegExp(r'appmanifest_\d+\.acf$').hasMatch(f.path))
              .take(2000)) {
        try {
          if (manifest.lengthSync() > 128 * 1024) continue;
          final content = manifest.readAsStringSync();
          final appId = RegExp(
            r'"appid"\s+"(\d+)"',
          ).firstMatch(content)?.group(1);
          final shortcut = steamShortcuts[appId];
          final name = RegExp(
            r'"name"\s+"([^"]+)"',
          ).firstMatch(content)?.group(1);
          final install = RegExp(
            r'"installdir"\s+"([^"/]+)"',
          ).firstMatch(content)?.group(1);
          if (name != null && install != null && install != '..') {
            entries.add(
              ActivityCandidate(
                id: '${Directory('$library/steamapps/common/$install').resolveSymbolicLinksSync()}/',
                name: name,
                kind: shortcut?.kind,
                iconBytes: shortcut?.iconBytes,
              ),
            );
          }
        } catch (_) {}
      }
    }
  }
  return entries;
}

class ActivityProcessScan {
  const ActivityProcessScan(this.catalogue, this.rules);
  final List<ActivityCandidate> catalogue;
  final Map<String, ActivityRule> rules;
  Future<List<ActivityCandidate>> call() =>
      _runningApplications(catalogue, rules);
}

Future<List<ActivityCandidate>> _runningApplications(
  List<ActivityCandidate> catalogue,
  Map<String, ActivityRule> rules,
) async {
  if (Platform.isWindows) return _windowsApplications();
  final result = <String, ActivityCandidate>{};
  for (final entry in Directory('/proc').listSync(followLinks: false)) {
    if (!RegExp(r'/\d+$').hasMatch(entry.path)) continue;
    try {
      final executable = Link('${entry.path}/exe').resolveSymbolicLinksSync();
      final match = matchRunningActivity(executable, catalogue);
      if (match == null && !rules.containsKey(executable)) continue;
      final base = executable.split('/').last.toLowerCase();
      // Old preview rules may have mistaken Steam for a game's shortcut.
      // A launcher alone is never proof that one of its games is running.
      if (base == 'steam') continue;
      if ([
        'crash',
        'update',
        'uninstall',
        'setup',
        'steamwebhelper',
        'wineserver',
      ].any(base.contains)) {
        continue;
      }
      result[executable] = ActivityCandidate(
        id: executable,
        name: match?.name ?? base,
        kind: match?.kind,
        iconBytes: match?.iconBytes,
      );
    } catch (_) {}
  }
  return result.values.toList();
}

Future<List<ActivityCandidate>> _windowsApplications() async {
  // One bounded snapshot; no window titles, command lines or process injection.
  final process = await Process.start('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    r'''
Add-Type -AssemblyName System.Drawing
$items = @(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 100 | ForEach-Object {
  try {
    $p = $_.Path
    if ($p) {
      $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($p)
      $stream = New-Object System.IO.MemoryStream
      if ($icon) { $bitmap = $icon.ToBitmap(); $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png); $bitmap.Dispose(); $icon.Dispose() }
      @{id=$p; name=$_.ProcessName; icon=[Convert]::ToBase64String($stream.ToArray())}
      $stream.Dispose()
    }
  } catch {}
})
ConvertTo-Json -InputObject $items -Compress
''',
  ]);
  final timer = Timer(const Duration(seconds: 8), () => process.kill());
  try {
    final errors = process.stderr.drain<void>();
    final out = await process.stdout.transform(utf8.decoder).join();
    await errors;
    if (await process.exitCode != 0 || out.length > 2 * 1024 * 1024) return [];
    final rows = jsonDecode(out);
    return rows is List
        ? rows
              .whereType<Map>()
              .map(
                (row) => ActivityCandidate(
                  id: row['id'],
                  name: row['name'],
                  iconBytes:
                      row['icon'] is String &&
                          (row['icon'] as String).length < 128 * 1024
                      ? base64Decode(row['icon'])
                      : null,
                ),
              )
              .toList()
        : [];
  } catch (_) {
    return [];
  } finally {
    timer.cancel();
  }
}

Future<ActivityCandidate?> _linuxMusic(ActivityArtworkCache artwork) async {
  try {
    final process = await Process.start('playerctl', [
      '--all-players',
      'metadata',
      '--format',
      '{{status}}\t{{playerName}}\t{{artist}}\t{{title}}\t{{mpris:artUrl}}\t{{position}}\t{{mpris:length}}',
    ]);
    final timer = Timer(const Duration(seconds: 2), () => process.kill());
    final errors = process.stderr.drain<void>();
    String output;
    try {
      output = await process.stdout.transform(utf8.decoder).join();
      await errors;
      if (await process.exitCode != 0) return null;
    } finally {
      timer.cancel();
    }
    final lines = output.split('\n')
      ..sort(
        (a, b) => (a.startsWith('Playing\t') ? 0 : 1).compareTo(
          b.startsWith('Playing\t') ? 0 : 1,
        ),
      );
    for (final line in lines) {
      final fields = line.split('\t');
      if (fields.length >= 4 &&
          (fields[0] == 'Playing' || fields[0] == 'Paused') &&
          fields[3].isNotEmpty) {
        final sampledAt = DateTime.now();
        return ActivityCandidate(
          id: 'music:${fields[1]}',
          name: _boundedText(fields[3], 128),
          kind: ActivityKind.music,
          details: _boundedText(fields[2], 256),
          iconBytes: fields.length > 4 ? await artwork.load(fields[4]) : null,
          playback: fields.length >= 7
              ? playbackFromMpris(
                  fields[5],
                  fields[6],
                  fields[0],
                  now: sampledAt,
                )
              : null,
        );
      }
    }
  } catch (_) {}
  return null;
}

ActivityPlayback? playbackFromMpris(
  String position,
  String length,
  String state, {
  DateTime? now,
}) {
  final p = int.tryParse(position), d = int.tryParse(length);
  if (p == null || d == null || p < 0 || d < 1000 || d > 86400000000) {
    return null;
  }
  return ActivityPlayback(
    positionMs: (p ~/ 1000).clamp(0, d ~/ 1000),
    durationMs: d ~/ 1000,
    sampledAt: now ?? DateTime.now(),
    playing: state == 'Playing',
  );
}

bool preferPlayerMusic(ActivityCandidate rpc, ActivityCandidate? player) =>
    rpc.kind == ActivityKind.music &&
    player != null &&
    player.playback?.playing != false;
