import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/user_activity.dart';
import 'activity_candidate.dart';
import 'activity_discovery.dart';

Future<List<ActivityCandidate>> loadWindowsGameCatalogue() async {
  final result = <ActivityCandidate>[];
  final data = Platform.environment['ProgramData'];
  if (data != null && data.isNotEmpty) {
    try {
      final manifests = Directory(
        '$data/Epic/EpicGamesLauncher/Data/Manifests',
      );
      await for (final file in manifests.list(followLinks: false).take(2048)) {
        if (file is! File || !file.path.toLowerCase().endsWith('.item')) {
          continue;
        }
        try {
          if (await file.length() > 256 * 1024) continue;
          result.addAll(
            parseEpicGameManifest(jsonDecode(await file.readAsString())),
          );
        } catch (_) {
          // Missing or changing launcher metadata does not affect other games.
        }
      }
    } on FileSystemException {
      // Epic may not be installed.
    }
  }
  try {
    final process = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      _readWindowsGameRecords,
    ]);
    final timer = Timer(const Duration(seconds: 6), () => process.kill());
    try {
      final errors = process.stderr.drain<void>();
      var remaining = 4096;
      await for (final line
          in process.stdout
              .transform(const Utf8Decoder(allowMalformed: true))
              .transform(const LineSplitter())) {
        if (--remaining < 0 || line.length > 16 * 1024) continue;
        try {
          result.addAll(parseWindowsGameRecord(jsonDecode(line)));
        } on FormatException {
          // The time limit can interrupt the last record.
        }
      }
      await errors;
      await process.exitCode;
    } finally {
      timer.cancel();
    }
  } on ProcessException {
    // Steam, Epic, and manual rules still work without PowerShell metadata.
  }
  return result;
}

List<ActivityCandidate> parseEpicGameManifest(Object? value) {
  if (value is! Map ||
      value['bIsApplication'] != true ||
      value['bIsIncompleteInstall'] == true ||
      value['bIsExecutable'] == false ||
      value['bIsUnrealEngine'] == true ||
      value['LaunchExecutable'] is! String ||
      (value['MainGameAppName'] is String &&
          (value['MainGameAppName'] as String).isNotEmpty &&
          value['MainGameAppName'] != value['AppName'])) {
    return [];
  }
  final categories = value['AppCategories'];
  if (categories is List &&
      categories.whereType<String>().any(
        (category) => category == 'addons' || category.startsWith('plugins'),
      )) {
    return [];
  }
  return _gameEntries(
    value['DisplayName'],
    value['InstallLocation'],
    value['LaunchExecutable'],
  );
}

/// Decode records emitted by the read-only Windows installation probe.
List<ActivityCandidate> parseWindowsGameRecord(Object? value) {
  if (value is! Map) return [];
  final source = value['source'];
  if (source == 'gog' &&
      !const {null, '', 0, '0'}.contains(value['dependsOn'])) {
    return [];
  }
  if (source == 'xbox' || source == 'gog') {
    return _gameEntries(value['name'], value['path'], value['exe']);
  }
  if (source == 'ubisoft' || source == 'ea' || source == 'battle.net') {
    return _gameEntries(value['name'], value['path'], null);
  }
  return [];
}

List<ActivityCandidate> _gameEntries(
  Object? displayName,
  Object? installPath,
  Object? executable,
) {
  if (displayName is! String || installPath is! String) return [];
  final name = displayName.trim();
  if (name.isEmpty ||
      name.length > 128 ||
      RegExp(r'[\x00-\x1f]').hasMatch(name) ||
      RegExp(
        r'^(?:battle\.net|ea(?: desktop| app)?|origin|ubisoft connect|uplay|gog galaxy|epic games launcher|unreal engine|xbox)(?:$| \d)',
        caseSensitive: false,
      ).hasMatch(name)) {
    return [];
  }
  final root = _localPath(installPath);
  if (root == null ||
      const {
        'games',
        'xboxgames',
        'gog games',
        'ea games',
        'epic games',
        'program files',
        'program files (x86)',
        'windows',
        'users',
        'downloads',
        'desktop',
        'temp',
      }.contains(root.split('/').last.toLowerCase())) {
    return [];
  }
  String? exact;
  if (executable is String && executable.trim().isNotEmpty) {
    final fragment = normalizeActivityPath(executable.trim());
    exact = _localPath(
      RegExp(r'^[A-Za-z]:/').hasMatch(fragment) ? fragment : '$root/$fragment',
    );
    final prefix = '${root.toLowerCase()}/';
    if (exact == null ||
        !exact.toLowerCase().startsWith(prefix) ||
        !exact.toLowerCase().endsWith('.exe')) {
      return [];
    }
  }
  return [
    if (exact != null && !isWindowsGameHelper(exact))
      ActivityCandidate(id: exact, name: name, kind: ActivityKind.game),
    ActivityCandidate(id: '$root/', name: name, kind: ActivityKind.game),
  ];
}

String? _localPath(String path) {
  var value = normalizeActivityPath(path.trim());
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  value = value.replaceFirst(RegExp(r'/+$'), '');
  if (!RegExp(r'^[A-Za-z]:/[^/]').hasMatch(value) ||
      RegExp(r'[\x00-\x1f<>:"|?*]').hasMatch(value.substring(2)) ||
      value
          .substring(3)
          .split('/')
          .any(
            (segment) =>
                segment.isEmpty ||
                segment.endsWith('.') ||
                segment.endsWith(' '),
          )) {
    return null;
  }
  return value;
}

const _readWindowsGameRecords = r'''
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
function Write-Game($source, $name, $path, $exe, $dependency) {
  if ($name -and $path) {
    @{source=$source; name=$name; path=$path; exe=$exe; dependsOn=$dependency} | ConvertTo-Json -Compress
  }
}
function Read-RegistryFolder($path) {
  Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue |
    Select-Object -First 2048 | ForEach-Object {
      Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
    }
}
$uplayNames = @{}
foreach ($base in @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\SOFTWARE')) {
  Read-RegistryFolder "$base\GOG.com\Games" | ForEach-Object {
    Write-Game 'gog' $_.gameName $_.path $_.exe $_.dependsOn
  }
  Read-RegistryFolder "$base\Microsoft\Windows\CurrentVersion\Uninstall" | ForEach-Object {
    if ($_.PSChildName -match '^Uplay Install (\d+)$') {
      $uplayNames[$Matches[1]] = $_.DisplayName
    } elseif ($_.UninstallString -match '[\\/]_{0,2}EAInstaller[\\/]') {
      Write-Game 'ea' $_.DisplayName $_.InstallLocation
    } elseif ($_.UninstallString -match 'Battle\.net.*\s--uid=\S+') {
      Write-Game 'battle.net' $_.DisplayName $_.InstallLocation
    }
  }
}
foreach ($base in @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\SOFTWARE')) {
  Read-RegistryFolder "$base\Ubisoft\Launcher\Installs" | ForEach-Object {
    if ($_.PSChildName -match '^\d+$' -and $_.InstallDir) {
      $title = $uplayNames[$_.PSChildName]
      if (!$title) { $title = [IO.Path]::GetFileName($_.InstallDir.TrimEnd([char[]]@('\','/'))) }
      Write-Game 'ubisoft' $title $_.InstallDir
    }
  }
}

$settings = New-Object System.Xml.XmlReaderSettings
$settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
$settings.XmlResolver = $null
$settings.MaxCharactersInDocument = 262144
foreach ($drive in [IO.DriveInfo]::GetDrives()) {
  if (!$drive.IsReady -or $drive.DriveType -ne [IO.DriveType]::Fixed) { continue }
  $root = $drive.RootDirectory.FullName
  $folders = @('XboxGames')
  try {
    $marker = Get-Item -LiteralPath (Join-Path $root '.GamingRoot') -Force -ErrorAction Stop
    if ($marker.Length -ge 10 -and $marker.Length -le 4096) {
      $bytes = [IO.File]::ReadAllBytes($marker.FullName)
      if ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ceq 'RGBX') {
        $folders += [Text.Encoding]::Unicode.GetString($bytes, 8, $bytes.Length - 8).Split([char]0)
      }
    }
  } catch {}
  foreach ($folder in ($folders | Select-Object -Unique -First 8)) {
    if (!$folder -or $folder -match '^[\\/]|[:*?"<>|]|(?:^|[\\/])\.{1,2}(?:[\\/]|$)') { continue }
    Get-ChildItem -LiteralPath (Join-Path $root $folder) -Directory -ErrorAction SilentlyContinue |
      Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
      Select-Object -First 512 | ForEach-Object {
        $content = Join-Path $_.FullName 'Content'
        $fallbackName = $_.Name
        $reader = $null
        try {
          $reader = [Xml.XmlReader]::Create((Join-Path $content 'MicrosoftGame.config'), $settings)
          $xml = New-Object Xml.XmlDocument
          $xml.XmlResolver = $null
          $xml.Load($reader)
          if ($xml.DocumentElement.LocalName -eq 'Game') {
            $visuals = $xml.SelectSingleNode('/*/*[local-name()="ShellVisuals"]')
            $title = if ($visuals) { $visuals.GetAttribute('DefaultDisplayName') }
            if (!$title -or $title -match '^ms-resource:') { $title = $fallbackName }
            $xml.SelectNodes('/*/*[local-name()="ExecutableList"]/*[local-name()="Executable"]') |
              Select-Object -First 16 | ForEach-Object {
                $exe = $_.GetAttribute('Name')
                if ($exe -and $_.GetAttribute('IsDevOnly') -ne 'true') {
                  Write-Game 'xbox' $title $content $exe
                }
              }
          }
        } catch {} finally { if ($reader) { $reader.Dispose() } }
      }
  }
}
''';
