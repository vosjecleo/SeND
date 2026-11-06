import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:deltiecord/models/saved_gif_reference.dart';
import 'package:deltiecord/services/gif_service.dart';
import 'package:deltiecord/services/personal_data.dart';
import 'package:deltiecord/services/gif_identity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => GifService.bind(null));
  test(
    'older uploaded favourites match a forwarded copy without rewriting records',
    () {
      const original = SavedGifReference(
        roomId: '!original:test',
        eventId: r'$old',
      );
      final forwarded = SavedGifReference(
        roomId: '!forwarded:test',
        eventId: r'$new',
        identity: gifIdentityFor(original.roomId, original.eventId),
      );
      expect(
        GifSearchResult.saved(
          original,
        ).matches(GifSearchResult.saved(forwarded)),
        true,
      );
      expect(
        GifSearchResult.saved(original).matches(
          GifSearchResult.saved(
            const SavedGifReference(
              roomId: '!unrelated:test',
              eventId: r'$other',
            ),
          ),
        ),
        false,
      );
    },
  );
  test(
    'uploaded GIF favourites sync references, never file keys or source captions',
    () async {
      final records = <String, Object?>{};
      final first = PersonalData(
        account: '@me:test',
        write: (key, value) async => records[key] = value,
      );
      await first.open({});
      addTearDown(first.close);
      GifService.bind(first);
      final reference = SavedGifReference.fromJson({
        'room_id': '!source:test',
        'event_id': r'$gif',
        'file': {
          'key': {'k': 'must-not-sync'},
          'iv': 'must-not-sync',
        },
        'body': 'Private caption',
      })!;
      final gif = GifSearchResult.saved(reference, width: 200, height: 100);
      final service = GifService();
      addTearDown(service.dispose);
      await service.toggleFavorite(gif);
      await first.flush();
      final serialized = jsonEncode(records);
      expect(serialized, isNot(contains('must-not-sync')));
      expect(serialized, isNot(contains('Private caption')));
      expect(gif.toJson()['message'], {
        'room_id': '!source:test',
        'event_id': r'$gif',
      });
      FlutterSecureStorage.setMockInitialValues({});
      final otherDevice = PersonalData(
        account: '@me:test',
        write: (key, value) async => records[key] = value,
      );
      await otherDevice.open(records);
      addTearDown(otherDevice.close);
      GifService.bind(otherDevice);
      final saved = (await service.favorites()).single;
      expect(saved.message!.roomId, '!source:test');
      expect(saved.message!.eventId, r'$gif');
      expect(saved.aspectRatio, 2);
    },
  );
  test(
    'private preview cache cannot cross account switches or stale resolutions',
    () async {
      Future<PersonalData> account(String name) async {
        final p = PersonalData(account: name, write: (_, _) async {});
        await p.open({});
        addTearDown(p.close);
        return p;
      }

      final a = await account('@a:test'), b = await account('@b:test');
      final gate = Completer<Uint8List>();
      GifService.bind(a, resolveSaved: (_) => gate.future);
      final service = GifService();
      addTearDown(service.dispose);
      final gif = GifSearchResult.saved(
        const SavedGifReference(roomId: '!source:test', eventId: r'$gif'),
      );
      final pending = service.preview(gif);
      GifService.bind(
        b,
        resolveSaved: (_) async =>
            throw StateError('Unavailable for this account'),
      );
      gate.complete(Uint8List.fromList([1]));
      await expectLater(pending, throwsStateError);
      await expectLater(service.preview(gif), throwsStateError);
    },
  );
  test(
    'paginated provider results preserve proportions and reject repeated page one',
    () {
      final data = <String, Object?>{
        'result': true,
        'data': {
          'current_page': 1,
          'has_next': true,
          'data': [
            {
              'type': 'gif',
              'title': 'Test',
              'file': {
                'sm': {
                  'gif': {
                    'url': 'https://static.klipy.com/a.gif',
                    'width': 200,
                    'height': 100,
                    'size': 1024,
                  },
                },
              },
            },
          ],
        },
      };
      final first = GifSearchPage.fromJson(data, 1);
      expect(first.items.single.aspectRatio, 2);
      expect(first.hasMore, true);
      final repeated = GifSearchPage.fromJson(data, 2);
      expect(repeated.items, isEmpty);
      expect(repeated.hasMore, false);
    },
  );
}
