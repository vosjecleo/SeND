import 'activity_candidate.dart';

String? steamShortcutAppId(String command) => RegExp(
  r'^\s*(?:"[^"\n]*steam"|\S*steam)\s+steam://rungameid/(\d+)(?:\s|$)',
).firstMatch(command)?.group(1);

ActivityCandidate? matchRunningActivity(
  String executable,
  List<ActivityCandidate> catalogue,
) {
  // Prefer an installation directory over a generic executable name.
  final installations =
      catalogue
          .where((e) => e.id.endsWith('/') && executable.startsWith(e.id))
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
