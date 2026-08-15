import 'package:deltiecord/services/emoji_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local emoji search resolves familiar aliases without network',
    () async {
      final matches = await EmojiRepository.instance.search('sob', limit: 3);
      expect(matches, isNotEmpty);
      expect(matches.first.emoji, '😭');
    },
  );

  test('every local emoji has a canonical searchable name', () async {
    final entries = await EmojiRepository.instance.load();
    expect(entries.length, greaterThan(1800));
    expect(entries.every((entry) => entry.name.trim().isNotEmpty), isTrue);
  });
}
