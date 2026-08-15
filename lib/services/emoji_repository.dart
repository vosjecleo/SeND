import 'dart:convert';

import 'package:flutter/services.dart';

const _familiarAliases = <String, List<String>>{
  '😭': ['sob', 'cry', 'loudly_crying'],
  '😂': ['joy', 'tears_of_joy'],
  '🤣': ['rofl'],
  '❤️': ['heart', 'love'],
  '👍': ['thumbsup', '+1'],
  '👎': ['thumbsdown', '-1'],
  '💀': ['skull', 'dead'],
  '🙏': ['pray', 'please'],
  '🔥': ['fire', 'lit'],
  '🎉': ['tada', 'party'],
  '👀': ['eyes'],
  '🤔': ['thinking'],
  '😅': ['sweat_smile'],
  '😎': ['sunglasses'],
};

class EmojiEntry {
  const EmojiEntry({
    required this.emoji,
    required this.name,
    required this.aliases,
  });

  final String emoji;
  final String name;
  final List<String> aliases;

  bool matches(String query) {
    final normalized = query.toLowerCase().replaceAll('_', ' ').trim();
    if (normalized.isEmpty) return true;
    return name.toLowerCase().contains(normalized) ||
        aliases.any((alias) => alias.toLowerCase().contains(normalized));
  }

  int score(String query) {
    final normalized = query.toLowerCase().replaceAll('_', ' ').trim();
    final lowerName = name.toLowerCase();
    if (aliases.any((alias) => alias.toLowerCase() == normalized)) return 0;
    if (lowerName == normalized) return 1;
    if (aliases.any((alias) => alias.toLowerCase().startsWith(normalized))) {
      return 2;
    }
    if (lowerName.startsWith(normalized)) return 3;
    return 4;
  }
}

class EmojiRepository {
  EmojiRepository._();

  static final instance = EmojiRepository._();
  Future<List<EmojiEntry>>? _loading;

  Future<List<EmojiEntry>> load() => _loading ??= _load();

  String? familiarEmoji(String alias) {
    final normalized = alias.toLowerCase().replaceAll('_', ' ').trim();
    for (final entry in _familiarAliases.entries) {
      if (entry.value.any(
        (candidate) => candidate.replaceAll('_', ' ') == normalized,
      )) {
        return entry.key;
      }
    }
    return null;
  }

  /// Returns the small set of conventional aliases without waiting for the
  /// complete local dataset to decode. This keeps composer completion instant
  /// on its first use while [search] loads the full catalogue in parallel.
  List<EmojiEntry> familiarMatches(String query, {int limit = 3}) {
    final normalized = query.toLowerCase().replaceAll('_', ' ').trim();
    if (normalized.isEmpty) return const [];
    final matches = <EmojiEntry>[];
    for (final aliasGroup in _familiarAliases.entries) {
      final aliases = aliasGroup.value;
      if (!aliases.any(
        (alias) =>
            alias.toLowerCase().replaceAll('_', ' ').contains(normalized),
      )) {
        continue;
      }
      matches.add(
        EmojiEntry(
          emoji: aliasGroup.key,
          name: aliases.first.replaceAll('_', ' '),
          aliases: aliases,
        ),
      );
      if (matches.length == limit) break;
    }
    return matches;
  }

  Future<List<EmojiEntry>> _load() async {
    final source = await rootBundle.loadString('assets/emoji/emojis.json');
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    return decoded.entries
        .map((entry) {
          final data = entry.value as Map<String, dynamic>;
          final aliases =
              (data['keywords'] as List? ?? const [])
                  .whereType<String>()
                  .toSet()
                ..addAll(_familiarAliases[entry.key] ?? const []);
          return EmojiEntry(
            emoji: entry.key,
            name: data['name'] as String? ?? entry.key,
            aliases: aliases.toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  Future<List<EmojiEntry>> search(String query, {int? limit}) async {
    final entries = await load();
    final matches = entries.where((entry) => entry.matches(query)).toList();
    matches.sort((a, b) {
      final score = a.score(query).compareTo(b.score(query));
      return score != 0 ? score : a.name.compareTo(b.name);
    });
    return limit == null || matches.length <= limit
        ? matches
        : matches.sublist(0, limit);
  }

  Future<EmojiEntry?> exactAlias(String alias) async {
    final normalized = alias.toLowerCase().replaceAll('_', ' ').trim();
    final entries = await load();
    return entries
        .where(
          (entry) =>
              entry.name.toLowerCase() == normalized ||
              entry.aliases.any(
                (candidate) => candidate.toLowerCase() == normalized,
              ),
        )
        .firstOrNull;
  }
}
