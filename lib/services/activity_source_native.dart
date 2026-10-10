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
import 'activity_pipe_windows.dart';

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
  final WindowsActivityPipe _windowsPipe = WindowsActivityPipe();
  final Map<Object, ActivityCandidate> _pipeRpc = {};
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
    } else if (settings.rpc && Platform.isWindows) {
      try {
        await _windowsPipe.start(
          (connection) => _acceptConnection(
            connection,
            connection.input,
            connection.add,
            connection.destroy,
            executable: connection.executable,
          ),
        );
        warning = null;
      } catch (error) {
        warning = error is StateError
            ? error.message.toString()
            : 'Windows IPC could not start.';
      }
    } else {
      await _closeRpc();
      warning = null;
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
      for (final activity in [
        ..._rpc.values,
        ..._pipeRpc.values,
      ].where((rpc) => !preferPlayerMusic(rpc, music)))
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
      ...detected.where(
        (e) =>
            ![..._rpc.values, ..._pipeRpc.values].any((rpc) => rpc.id == e.id),
      ),
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
    _acceptConnection(socket, socket, socket.add, socket.destroy);
  }

  void _acceptConnection(
    Object socket,
    Stream<List<int>> input,
    void Function(List<int>) write,
    void Function() destroy, {
    String? executable,
  }) {
    var buffer = <int>[];
    String? clientId;
    Timer? timeout;
    void finish() {
      timeout?.cancel();
      _clients.remove(socket);
      _rpc.remove(socket);
      _pipeRpc.remove(socket);
      destroy();
    }

    void send(int opcode, Object data) {
      final payload = utf8.encode(jsonEncode(data));
      final header = ByteData(8)
        ..setUint32(0, opcode, Endian.little)
        ..setUint32(4, payload.length, Endian.little);
      write([...header.buffer.asUint8List(), ...payload]);
    }

    timeout = Timer(const Duration(seconds: 10), finish);
    input.listen(
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
                  _pipeRpc.remove(socket);
                } else if (activity is Map) {
                  final pid = args['pid'];
                  String? exe = executable;
                  if (Platform.isLinux && pid is int && pid > 0) {
                    try {
                      exe = Link('/proc/$pid/exe').resolveSymbolicLinksSync();
                    } catch (_) {}
                  }
                  final candidate = ActivityCandidate(
                    id: exe ?? 'rpc:$clientId',
                    name: exe == null
                        ? 'Application $clientId'
                        : normalizeActivityPath(exe).split('/').last,
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
                  if (socket is Socket) {
                    _rpc[socket] = candidate;
                  } else {
                    _pipeRpc[socket] = candidate;
                  }
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
    await _windowsPipe.close();
    _pipeRpc.clear();
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

Future<Uint8List?> _icon(String? path) async {
  if (path == null ||
      !(path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path))) {
    return null;
  }
  try {
    final file = File(path);
    if (file.lengthSync() > 1024 * 1024) return null;
    var bytes = file.readAsBytesSync();
    if (path.toLowerCase().endsWith('.svg')) {
      // Stdin gives librsvg no filesystem base URL for linked resources. Only
      // installed local icons are considered; never execute desktop commands.
      final process = await Process.start('rsvg-convert', [
        '-w',
        '96',
        '-h',
        '96',
        '--keep-aspect-ratio',
      ]);
      final timer = Timer(const Duration(seconds: 2), () => process.kill());
      try {
        final errors = process.stderr.drain<void>();
        process.stdin.add(bytes);
        unawaited(process.stdin.close().catchError((_) {}));
        final output = BytesBuilder(copy: false);
        await for (final chunk in process.stdout) {
          if (output.length + chunk.length > 1024 * 1024) {
            process.kill();
            return null;
          }
          output.add(chunk);
        }
        await errors;
        if (await process.exitCode != 0) return null;
        bytes = output.takeBytes();
      } finally {
        timer.cancel();
        process.kill();
      }
    }
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width > 2048 || info.height > 2048) return null;
    final decoded = decoder?.decodeFrame(0);
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

Future<List<ActivityCandidate>> loadLocalActivityCatalogue() async {
  final homeDir = Platform.environment['HOME'] ?? '';
  final data = Platform.environment['XDG_DATA_HOME'] ?? '$homeDir/.local/share';
  final roots = [
    data,
    ...(Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
        .split(':'),
  ];
  final entries = <ActivityCandidate>[];
  final steamShortcuts = <String, ActivityCandidate>{};
  for (final root in Platform.isLinux ? roots : <String>[]) {
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
        final iconPath = findLocalActivityIcon(fields['Icon'], roots);
        final entry = ActivityCandidate(
          id: executable,
          name: fields['Name']!,
          kind: categories.contains('Game') ? ActivityKind.game : null,
          iconBytes: await _icon(iconPath),
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
    if (Platform.isLinux) ...[
      '$homeDir/.local/share/Steam',
      '$homeDir/.steam/steam',
      '$homeDir/.var/app/com.valvesoftware.Steam/.local/share/Steam',
    ],
    if (Platform.isWindows) ..._windowsSteamRoots(),
  ]) {
    final libraries = <String>{steam};
    try {
      final vdf = File('$steam/steamapps/libraryfolders.vdf');
      if (vdf.lengthSync() < 1024 * 1024) {
        libraries.addAll(
          RegExp(r'"path"\s+"([^"]+)"')
              .allMatches(vdf.readAsStringSync())
              .map(
                (m) =>
                    normalizeActivityPath(m.group(1)!.replaceAll(r'\\', r'\')),
              ),
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
                id: '${normalizeActivityPath(Directory('$library/steamapps/common/$install').resolveSymbolicLinksSync())}/',
                name: name,
                kind: appId == '431960'
                    ? ActivityKind.application
                    : ActivityKind.game,
                steamAppId: appId,
                iconBytes:
                    shortcut?.iconBytes ?? await _steamIcon(steam, appId),
              ),
            );
          }
        } catch (_) {}
      }
    }
  }
  return entries;
}

/// Resolve installed raster artwork without launching .desktop commands.
/// Search common icon themes as well as hicolor; many distributions put app
/// icons only in their selected theme or in a Flatpak export directory.
String? findLocalActivityIcon(String? name, List<String> roots) {
  if (name == null || name.isEmpty) return null;
  if (name.startsWith('/')) return File(name).existsSync() ? name : null;
  if (name.contains('/') || name.contains('..')) return null;
  for (final root in roots) {
    final themes = <String>{'hicolor'};
    final icons = Directory('$root/icons');
    if (icons.existsSync()) {
      themes.addAll(
        icons
            .listSync(followLinks: false)
            .whereType<Directory>()
            .take(32)
            .map((directory) => directory.path.split('/').last),
      );
    }
    final filenames =
        name.endsWith('.png') || name.endsWith('.svg') || name.endsWith('.webp')
        ? [name]
        : ['$name.png', '$name.webp', '$name.svg'];
    for (final filename in filenames) {
      for (final theme in themes) {
        for (final size in [
          '256x256',
          '128x128',
          '96x96',
          '64x64',
          '48x48',
          '32x32',
          'scalable',
          'apps/48',
          'apps/64',
          'apps/128',
        ]) {
          for (final path in [
            '$root/icons/$theme/$size/apps/$filename',
            '$root/icons/$theme/$size/$filename',
          ]) {
            if (File(path).existsSync()) return path;
          }
        }
      }
      final pixmap = '$root/pixmaps/$filename';
      if (File(pixmap).existsSync()) return pixmap;
    }
  }
  return null;
}

List<String> _windowsSteamRoots() {
  final roots = <String>{
    '${Platform.environment['ProgramFiles(x86)'] ?? 'C:/Program Files (x86)'}/Steam',
    '${Platform.environment['ProgramFiles'] ?? 'C:/Program Files'}/Steam',
  };
  try {
    final query = Process.runSync('reg.exe', [
      'query',
      r'HKCU\Software\Valve\Steam',
      '/v',
      'SteamPath',
    ]);
    final path = RegExp(
      r'SteamPath\s+REG_SZ\s+(.+)',
    ).firstMatch('${query.stdout}')?.group(1)?.trim();
    if (path != null) roots.add(path);
  } catch (_) {}
  return roots.map(normalizeActivityPath).toList();
}

Future<Uint8List?> _steamIcon(String steam, String? id) async {
  if (id == null) return null;
  final cache = Directory('$steam/appcache/librarycache');
  if (!cache.existsSync()) return null;
  final paths = <String>[
    '$steam/appcache/librarycache/$id/icon.png',
    '$steam/appcache/librarycache/$id/${id}_icon.jpg',
    if (Directory('${cache.path}/$id').existsSync())
      ...Directory('${cache.path}/$id')
          .listSync(followLinks: false)
          .whereType<File>()
          .map((f) => f.path)
          .take(80),
    ...cache
        .listSync(followLinks: false)
        .whereType<File>()
        .where(
          (f) => f.path.split(Platform.pathSeparator).last.startsWith('${id}_'),
        )
        .map((f) => f.path)
        .take(30),
  ];
  int score(String path) {
    final name = normalizeActivityPath(path).split('/').last;
    if (name.contains('icon') || RegExp(r'^[a-f0-9]{40}\.').hasMatch(name)) {
      return 0;
    }
    return name == 'header.jpg' ? 1 : 2;
  }

  paths.sort((a, b) => score(a).compareTo(score(b)));
  for (final path in paths) {
    final bytes = await _icon(path);
    if (bytes != null) return bytes;
  }
  return null;
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
  if (Platform.isWindows) return _windowsApplications(catalogue, rules);
  final result = <String, ActivityCandidate>{};
  for (final entry in Directory('/proc').listSync(followLinks: false)) {
    if (!RegExp(r'/\d+$').hasMatch(entry.path)) continue;
    try {
      var executable = Link('${entry.path}/exe').resolveSymbolicLinksSync();
      var match = matchRunningActivity(executable, catalogue);
      if (executable.split('/').last == 'java') {
        final command = File('${entry.path}/cmdline').openSync();
        List<String> args;
        try {
          args = utf8
              .decode(command.readSync(65536), allowMalformed: true)
              .split('\u0000');
        } finally {
          command.closeSync();
        }
        if (isMinecraftClientArguments(args)) {
          final icon = catalogue
              .where((item) => item.name.toLowerCase() == 'minecraft')
              .firstOrNull
              ?.iconBytes;
          final assetIndex = args.indexOf('--assetsDir');
          final assets = assetIndex >= 0 && assetIndex + 1 < args.length
              ? args[assetIndex + 1]
              : '${Platform.environment['HOME']}/.minecraft/assets';
          match = ActivityCandidate(
            id: executable,
            name: 'Minecraft',
            kind: ActivityKind.game,
            iconBytes: icon ?? await loadMinecraftActivityIcon(assets),
          );
        }
      }
      // Read only this user's process metadata, locally. Steam's identity also
      // distinguishes GoldSrc games sharing hl.exe (e.g. Opposing Force).
      String? steamId;
      try {
        final env = File('${entry.path}/environ').openSync();
        String contents;
        try {
          contents = utf8.decode(env.readSync(65536), allowMalformed: true);
        } finally {
          env.closeSync();
        }
        steamId = RegExp(
          r'(?:^|\x00)SteamAppId=(\d+)(?:\x00|$)',
        ).firstMatch(contents)?.group(1);
      } catch (_) {}
      if (steamId != null && steamId != '0') {
        final app = catalogue.where((c) => c.steamAppId == steamId).firstOrNull;
        final command = File('${entry.path}/cmdline').openSync();
        List<String> args;
        try {
          args = utf8
              .decode(command.readSync(65536), allowMalformed: true)
              .split('\u0000');
        } finally {
          command.closeSync();
        }
        final gameExe = args
            .where((arg) => arg.toLowerCase().endsWith('.exe'))
            .firstOrNull;
        final runtimeName = executable.split('/').last.toLowerCase();
        final wineProcess =
            runtimeName.startsWith('wine') || runtimeName.endsWith('.exe');
        if (app != null &&
            wineProcess &&
            gameExe != null &&
            !isActivityHelper(gameExe)) {
          // Wine maps Z: to the host root. Relative executables belong to the
          // identified Steam installation; never classify wineserver itself.
          final normalized = normalizeActivityPath(gameExe);
          executable =
              normalized.startsWith('Z:/') || normalized.startsWith('z:/')
              ? normalized.substring(2)
              : normalized.contains('/')
              ? normalized
              : '${app.id}$normalized';
          match = app;
        } else if (app != null && match != null) {
          match = app;
        }
      }
      if (match == null && !rules.containsKey(executable)) continue;
      final base = executable.split('/').last.toLowerCase();
      // Old preview rules may have mistaken Steam for a game's shortcut.
      // A launcher alone is never proof that one of its games is running.
      if (isActivityHelper(executable)) continue;
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
        steamAppId: match?.steamAppId,
        priority: match?.steamAppId == null ? 0 : 20,
      );
    } catch (_) {}
  }
  return rankActivities(result.values);
}

bool isMinecraftClientArguments(List<String> args) => args.any(
  {
    'net.minecraft.client.main.Main',
    'net.fabricmc.loader.impl.launch.knot.KnotClient',
    'net.fabricmc.loader.launch.knot.KnotClient',
  }.contains,
);

Future<Uint8List?> loadMinecraftActivityIcon(String assets) async {
  if (!assets.startsWith('/')) return null;
  try {
    final indexes = Directory('$assets/indexes');
    if (!indexes.existsSync()) return null;
    final files =
        indexes
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .take(32)
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    for (final file in files.take(4)) {
      if (file.lengthSync() > 8 * 1024 * 1024) continue;
      final index = jsonDecode(file.readAsStringSync());
      final objects = index is Map ? index['objects'] : null;
      if (objects is! Map) continue;
      for (final name in [
        'icons/icon_256x256.png',
        'icons/icon_32x32.png',
        'icons/icon_16x16.png',
      ]) {
        final entry = objects[name];
        final hash = entry is Map ? entry['hash'] : null;
        if (hash is! String || !RegExp(r'^[a-f0-9]{40}$').hasMatch(hash)) {
          continue;
        }
        final bytes = await _icon(
          '$assets/objects/${hash.substring(0, 2)}/$hash',
        );
        if (bytes != null) return bytes;
      }
    }
  } catch (_) {
    // Missing local artwork leaves the controller placeholder in place.
  }
  return null;
}

Future<List<ActivityCandidate>> _windowsApplications(
  List<ActivityCandidate> catalogue,
  Map<String, ActivityRule> rules,
) async {
  // One bounded snapshot; no window titles, command lines or process injection.
  final process = await Process.start('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    r'''
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class SendWindows { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p); }'
[uint32]$foreground = 0
[void][SendWindows]::GetWindowThreadProcessId([SendWindows]::GetForegroundWindow(), [ref]$foreground)
$items = @(Get-Process | Select-Object -First 2048 | ForEach-Object {
  try {
    $p = $_.Path
    if ($p) {
      $icon = if ($_.MainWindowHandle -ne 0) { [System.Drawing.Icon]::ExtractAssociatedIcon($p) } else { $null }
      $stream = New-Object System.IO.MemoryStream
      if ($icon) { $bitmap = $icon.ToBitmap(); $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png); $bitmap.Dispose(); $icon.Dispose() }
      @{id=$p; name=$_.ProcessName; window=($_.MainWindowHandle -ne 0); foreground=($_.Id -eq $foreground); title=$_.FileVersionInfo.ProductName; icon=[Convert]::ToBase64String($stream.ToArray())}
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
    if (rows is! List) return [];
    final candidates = <ActivityCandidate>[];
    for (final row in rows.whereType<Map>()) {
      final path = row['id'];
      if (path is! String || isActivityHelper(path)) continue;
      final match = matchRunningActivity(path, catalogue);
      if (row['window'] != true && match == null && !rules.containsKey(path)) {
        continue;
      }
      candidates.add(
        ActivityCandidate(
          id: path,
          name:
              match?.name ??
              (row['title'] is String &&
                      (row['title'] as String).trim().isNotEmpty
                  ? row['title']
                  : row['name']),
          kind: match?.kind,
          steamAppId: match?.steamAppId,
          priority:
              (row['foreground'] == true ? 100 : 0) +
              (row['window'] == true ? 40 : 0) +
              (match != null ? 20 : 0),
          iconBytes:
              row['icon'] is String &&
                  (row['icon'] as String).isNotEmpty &&
                  (row['icon'] as String).length < 128 * 1024
              ? base64Decode(row['icon'])
              : match?.iconBytes,
        ),
      );
    }
    return rankActivities(candidates);
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
