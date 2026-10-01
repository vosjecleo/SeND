import 'activity_candidate.dart';

String normalizeActivityPath(String path) => path.replaceAll('\\', '/');

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
