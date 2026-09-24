import 'package:characters/characters.dart';

const forumPostKey = 'net.deltiecord.forum.post';

/// Optional presentation metadata. The Matrix body remains readable in clients
/// that do not implement forums; no access control is encoded here.
class ForumPost {
  const ForumPost({required this.title, this.tags = const []});
  final String title;
  final List<String> tags;

  factory ForumPost.validated(String title, Iterable<String> tags) {
    final clean = title.trim();
    if (clean.isEmpty || clean.characters.length > 120) {
      throw const FormatException('Use a post title of 1–120 characters.');
    }
    final normalized = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (normalized.length > 5 ||
        normalized.any((tag) => tag.characters.length > 24)) {
      throw const FormatException(
        'Use at most five tags of up to 24 characters.',
      );
    }
    return ForumPost(title: clean, tags: normalized);
  }

  static ForumPost? fromJson(Object? value) {
    if (value is! Map || value['title'] is! String) return null;
    try {
      return ForumPost.validated(
        value['title'] as String,
        value['tags'] is List
            ? (value['tags'] as List).whereType<String>()
            : const [],
      );
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> toJson() => {'version': 1, 'title': title, 'tags': tags};
}
