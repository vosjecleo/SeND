import 'dart:async';
import 'dart:convert';
import 'package:deltiecord/services/gif_category_cache.dart';
import 'package:deltiecord/services/gif_categories.dart';
import 'package:deltiecord/services/gif_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RateLimitedService extends GifService {
  int calls = 0;
  @override
  Future<List<GifSearchResult>> categoryLinks(String query) async {
    calls++;
    throw const GifSearchException('Rate limited', 'http_429', status: 429);
  }
}

void main() {
  test(
    'warming stops immediately at the provider quota instead of probing remaining categories',
    () async {
      final service = _RateLimitedService();
      addTearDown(service.dispose);
      await service.warmCategories();
      expect(service.calls, 1);
    },
  );
  test(
    'fixed categories fill complete rows after favourites and frequently used',
    () {
      expect(gifCategorySearches.first, '');
      expect(
        gifCategorySearches.toSet(),
        hasLength(gifCategorySearches.length),
      );
      expect(gifCategorySearches.length.isEven, true);
      expect(
        gifCategorySearches,
        containsAll(['Angry', 'Kitten', 'Good morning']),
      );
    },
  );
  test(
    'only five public link records persist, survive restart and expire at twelve hours',
    () async {
      var now = DateTime.utc(2026, 11, 5);
      String? stored;
      var loads = 0;
      Future<List<Map<String, Object?>>> load() async {
        loads++;
        return [
          for (var i = 0; i < 24; i++)
            {
              'title': 'Result $i',
              'preview_url': 'https://static.klipy.com/preview-$i.gif',
              'share_url': 'https://static.klipy.com/share-$i.gif',
              'width': 200,
              'height': 100,
              'bytes': 'must-not-be-stored',
              'message': {'room_id': '!private:test'},
            },
        ];
      }

      GifCategoryCache open() => GifCategoryCache(
        read: () async => stored,
        write: (value) async => stored = value,
        clock: () => now,
      );
      final cache = open();
      expect(await cache.get('Love', load), hasLength(5));
      expect(loads, 1);
      expect(stored, isNot(contains('must-not-be-stored')));
      expect(stored, isNot(contains('private:test')));
      expect(
        (jsonDecode(stored!)['entries']['Love']['links'] as List),
        hasLength(5),
      );
      now = now.add(const Duration(hours: 11, minutes: 59));
      expect(await open().get('Love', load), hasLength(5));
      expect(loads, 1);
      now = now.add(const Duration(minutes: 1));
      expect(await open().get('Love', load), hasLength(5));
      expect(loads, 2);
    },
  );
  test(
    'parallel openings share one request, and failures do not poison a category',
    () async {
      final gate = Completer<List<Map<String, Object?>>>();
      var loads = 0;
      final cache = GifCategoryCache(
        read: () async => null,
        write: (_) async {},
      );
      Future<List<Map<String, Object?>>> load() {
        loads++;
        return gate.future;
      }

      final a = cache.get('', load), b = cache.get('', load);
      gate.complete([
        {
          'preview_url': 'https://static.klipy.com/p.gif',
          'share_url': 'https://static.klipy.com/g.gif',
        },
      ]);
      expect(await a, hasLength(1));
      expect(await b, hasLength(1));
      expect(loads, 1);
      await expectLater(
        cache.get('Angry', () async => throw StateError('Temporary')),
        throwsStateError,
      );
      expect(await cache.get('Angry', () async => []), isEmpty);
      await expectLater(
        cache.get('personal typed query', load),
        throwsArgumentError,
      );
    },
  );
  test('malformed, oversized and future-dated caches safely reload', () async {
    final now = DateTime.utc(2026, 11, 5);
    for (final stored in [
      'bad json',
      'x' * (GifCategoryCache.maximumCharacters + 1),
      jsonEncode({
        'version': 1,
        'entries': {
          '': {
            'at': now.add(const Duration(days: 1)).millisecondsSinceEpoch,
            'links': [],
          },
        },
      }),
    ]) {
      var fetched = false;
      final cache = GifCategoryCache(
        read: () async => stored,
        write: (_) async {},
        clock: () => now,
      );
      await cache.get('', () async {
        fetched = true;
        return [];
      });
      expect(fetched, true);
    }
  });
}
