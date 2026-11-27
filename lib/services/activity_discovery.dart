import 'activity_candidate.dart';
import '../models/user_activity.dart';

// Steam also distributes utilities, not just games.
ActivityKind steamActivityKind(String? appId) =>
    const {'431960', '3256420'}.contains(appId)
    ? ActivityKind.application
    : ActivityKind.game;

String normalizeActivityPath(String path) => path.replaceAll('\\', '/');

bool isSpotifyCandidate(ActivityCandidate candidate) =>
    normalizeActivityPath(
      candidate.id,
    ).split(RegExp(r'[/!:]+')).any(isSpotifyActivityIdentity) ||
    isSpotifyActivityIdentity(candidate.name);

bool isManualActivityUtility(ActivityCandidate candidate) {
  if (const {'431960', '3256420'}.contains(candidate.steamAppId)) return true;
  bool utility(String value) =>
      const {
        'wallpaperengine',
        'wallpaper32',
        'wallpaper64',
        'simplesight',
        'crosshairx',
        'crosshairv2',
      }.contains(
        value
            .toLowerCase()
            .replaceFirst(RegExp(r'\.(exe|desktop)$'), '')
            .replaceAll(RegExp(r'[ _-]+'), ''),
      );
  return utility(candidate.name.trim()) ||
      normalizeActivityPath(candidate.id).split('/').any(utility);
}

bool allowsActivitySharing(ActivityCandidate candidate, ActivityRule? rule) {
  if (isSpotifyCandidate(candidate) && !candidate.mediaSession) return false;
  return rule?.allowed ??
      (candidate.kind != null && !isManualActivityUtility(candidate));
}

ActivityKind? sharedActivityKind(
  ActivityCandidate candidate,
  ActivityRule? rule,
) => isSpotifyCandidate(candidate) && candidate.mediaSession
    ? ActivityKind.music
    : rule?.kind ?? candidate.kind;

String sharedActivityName(ActivityCandidate candidate, ActivityRule? rule) =>
    (isSpotifyCandidate(candidate) && candidate.mediaSession
            ? candidate.name
            : rule?.name ?? candidate.name)
        .trim();

bool isActivityHelper(String path) {
  final name = normalizeActivityPath(path).split('/').last.toLowerCase();
  return RegExp(
        r'(^|[_.-])(crash|crashpad|crashreport|crashreporter|update|updater|uninstall|setup|launcher|cef)([_.-]|$)',
      ).hasMatch(name) ||
      [
        'steam',
        'steam.exe',
        'steamwebhelper.exe',
        'steamwebhelper',
        'wineserver',
        'wine',
        'wine64',
        'wine-preloader',
        'wine64-preloader',
        'conhost.exe',
        'services.exe',
        'explorer.exe',
        'rpcss.exe',
      ].contains(name);
}

/// Installation folders can include launchers and tools alongside the game.
/// Keep those available for manual classification but don't infer a game.
bool isWindowsGameHelper(String path) {
  final segments = normalizeActivityPath(path).toLowerCase().split('/');
  final exe = segments.last.replaceFirst(RegExp(r'\.exe$'), '');
  return isActivityHelper(path) ||
      segments.any(
        const {
          '__installer',
          '_commonredist',
          'redist',
          'redistributables',
          'easyanticheat',
          'battleye',
          'prerequisites',
        }.contains,
      ) ||
      RegExp(
        r'launcher|crash(?:pad|handler|report)|anti.?cheat|dedicated.?server|(?:^|[_.-])(?:server|editor|config|benchmark)(?:$|[_.-])|^(?:unins\d*|setup|updater|vc_?redist.*|dxsetup|beservice.*|startprotectedgame|epicwebhelper|ubisoftconnect|upc|eadesktop|ealaunchhelper|battle\.net|galaxyclient|javaw?)$',
      ).hasMatch(exe);
}

/// Index once per snapshot; a game's precise executable beats another
/// installation's directory fallback. Directory-only matches need a window
/// (or Steam's existing manifest match) so background helpers aren't games.
class WindowsGameIndex {
  WindowsGameIndex(Iterable<ActivityCandidate> catalogue) {
    for (final item in catalogue) {
      final key = _key(item.id);
      final index = key.endsWith('/') ? _directories : _executables;
      index.putIfAbsent(key, () => item);
    }
  }

  final _directories = <String, ActivityCandidate>{};
  final _executables = <String, ActivityCandidate>{};

  static String _key(String path) {
    final key = normalizeActivityPath(path).toLowerCase();
    if (key.startsWith('//?/unc/')) return '//${key.substring(8)}';
    if (RegExp(r'^//\?/[a-z]:/').hasMatch(key)) return key.substring(4);
    return key;
  }

  ActivityCandidate? match(String executable, {required bool window}) {
    final key = _key(executable);
    if (isWindowsGameHelper(key)) return null;
    var end = key.lastIndexOf('/');
    ActivityCandidate? directory;
    while (end > 2) {
      directory = _directories[key.substring(0, end + 1)];
      if (directory != null) break;
      end = key.lastIndexOf('/', end - 1);
    }
    // Existing Steam utility classification takes precedence for the same
    // install even if another store registered an exact executable.
    if (directory != null && isManualActivityUtility(directory)) {
      return window || directory.steamAppId != null ? directory : null;
    }
    return _executables[key] ??
        (window || directory?.steamAppId != null ? directory : null);
  }
}

/// Ranking is local only. Prefer a game's real window and retain deterministic
/// results when several helper processes belong to the same installation.
List<ActivityCandidate> rankActivities(Iterable<ActivityCandidate> candidates) {
  final ranked = candidates.toList()
    ..sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      return priority != 0 ? priority : a.id.compareTo(b.id);
    });
  final seen = <String>{};
  return ranked.where((c) => seen.add(c.steamAppId ?? c.id)).toList();
}

String? steamShortcutAppId(String command) => RegExp(
  r'^\s*(?:"[^"\n]*steam"|\S*steam)\s+steam://rungameid/(\d+)(?:\s|$)',
).firstMatch(command)?.group(1);

ActivityCandidate? matchRunningActivity(
  String executable,
  List<ActivityCandidate> catalogue,
) {
  executable = normalizeActivityPath(executable);
  // Prefer an installation directory over a generic executable name.
  final installations =
      catalogue
          .where(
            (e) =>
                e.id.endsWith('/') &&
                (RegExp(r'^[A-Za-z]:/').hasMatch(executable)
                    ? executable.toLowerCase().startsWith(e.id.toLowerCase())
                    : executable.startsWith(e.id)),
          )
          .toList()
        ..sort((a, b) => b.id.length.compareTo(a.id.length));
  if (installations.isNotEmpty) return installations.first;
  return catalogue
      .where(
        (e) =>
            !e.id.endsWith('/') &&
            (e.id == executable ||
                (!e.id.contains('/') && e.id == executable.split('/').last)),
      )
      .firstOrNull;
}
