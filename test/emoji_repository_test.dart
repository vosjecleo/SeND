import 'package:deltiecord/services/favourite_reactions_store.dart';
import 'package:deltiecord/services/emoji_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('completion ranks frequency before prefix relevance and truncation', () {
    EmojiEntry entry(String name, String key) => EmojiEntry(
      emoji: key,
      name: name,
      aliases: [name],
      category: EmojiCategory.custom,
    );
    final matches = rankEmojiCompletions(
      [
        entry('happy', 'unused'),
        entry('halo', 'other'),
        entry('hand', 'another'),
        entry('fir_hangry', 'frequent'),
        entry('unrelated', 'most-used'),
      ],
      'ha',
      {'frequent': 100, 'most-used': 200},
    );
    expect(matches.map((e) => e.shortcode), ['fir_hangry', 'halo', 'hand']);
    expect(matches, hasLength(3));
  });
  test(
    'equal usage retains match relevance and deterministic alias ordering',
    () {
      final entries = [
        for (final name in ['fir_hangry', 'happy', 'ha'])
          EmojiEntry(
            emoji: name,
            name: name,
            aliases: [name],
            category: EmojiCategory.custom,
          ),
      ];
      expect(rankEmojiCompletions(entries, 'ha', {}).map((e) => e.shortcode), [
        'ha',
        'happy',
        'fir_hangry',
      ]);
    },
  );

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

  test('closed-form familiar aliases resolve exactly', () async {
    expect((await EmojiRepository.instance.exactAlias('sob'))?.emoji, '😭');
    expect(
      (await EmojiRepository.instance.exactAlias('loudly_crying'))?.emoji,
      '😭',
    );
  });

  test('emoji catalogue exposes browse categories', () async {
    final entries = await EmojiRepository.instance.load();
    expect(
      entries.firstWhere((entry) => entry.emoji == '🐵').category,
      EmojiCategory.animalsAndNature,
    );
    expect(
      entries.firstWhere((entry) => entry.emoji == '🏁').category,
      EmojiCategory.flags,
    );
  });

  test('complete catalogue finds ordinary colon-completion terms', () async {
    final matches = await EmojiRepository.instance.search('cat', limit: 3);
    expect(matches, isNotEmpty);
    expect(matches.every((entry) => entry.matches('cat')), isTrue);
  });

  test('editable alias overrides provide the canonical display name', () async {
    final crying = (await EmojiRepository.instance.search('sob')).first;
    expect(crying.name, 'Loudly crying face');
  });

  test(
    'sending counts complete Unicode emoji and custom IDs, not literal aliases',
    () async {
      final store = FavouriteReactionsStore.instance;
      final before = store.emojiUsage['😭'] ?? 0;
      await store.recordSentMessage(
        '😭 :not_sent: :wave:',
        '<img data-mx-emoticon src="mxc://test/wave" alt=":wave:">',
      );
      expect(store.emojiUsage['😭'], before + 1);
      expect(store.emojiUsage.containsKey(':not_sent:'), isFalse);
      expect(store.emojiUsage['mxc://test/wave'], greaterThan(0));
    },
  );

  test(
    'primary shortcodes beat incidental keywords; sobbing stays an alias',
    () async {
      final repository = EmojiRepository.instance;
      for (final pair in {
        'grinning': '😀',
        'smile': '😄',
        'confounded': '😖',
        'sob': '😭',
        'sobbing': '😭',
      }.entries) {
        expect((await repository.exactAlias(pair.key))?.emoji, pair.value);
      }
      expect(
        (await repository.search('cheerful')).any((e) => e.emoji == '😀'),
        isTrue,
      );
      final entries = await repository.load();
      expect(entries.every((e) => e.shortcode.isNotEmpty), isTrue);
      expect(
        entries.firstWhere((e) => e.emoji == '😖').shortcode,
        'confounded',
      );
    },
  );
}
