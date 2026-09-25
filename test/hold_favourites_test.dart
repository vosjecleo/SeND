import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:deltiecord/services/gif_service.dart';
import 'package:deltiecord/ui/gif_favourite_button.dart';
import 'package:deltiecord/services/favourite_reactions_store.dart';
import 'package:deltiecord/ui/advanced_chat_dialogs.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'widget_test.dart' show FakeBackend;

class Favourites extends GifService {
  int toggles = 0;
  @override
  Future<List<GifSearchResult>> favorites() async => [];
  @override
  Future<bool> toggleFavorite(GifSearchResult gif) async => (++toggles).isOdd;
  @override
  bool isFavorite(GifSearchResult gif) => toggles.isOdd;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('sticker hold favourites without selecting; star has no button', (
    tester,
  ) async {
    final uri = Uri.parse('mxc://test/hold-sticker');
    final store = FavouriteReactionsStore.instance;
    await tester.runAsync(store.load);
    if (store.isStickerFavourite(uri)) {
      await tester.runAsync(() => store.toggleSticker(uri));
    }
    final sticker = StickerSummary(id: 'one', name: 'Sticker', mxcUri: uri);
    final backend = FakeBackend()
      ..stickerPackList = [
        StickerPackSummary(id: 'pack', name: 'Pack', stickers: [sticker]),
      ];
    StickerSummary? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  chosen = await showStickerPicker(context, backend),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('sticker-pack-one'));
    expect(
      find.descendant(of: tile, matching: find.byType(IconButton)),
      findsNothing,
    );
    await tester.longPress(tile);
    await tester.pump();
    expect(chosen, isNull);
    expect(store.isStickerFavourite(uri), isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(chosen, same(sticker));
    await tester.runAsync(() => store.toggleSticker(uri));
  });
  testWidgets(
    'normal tap and drag never favourite; hold toggles exactly once',
    (tester) async {
      final service = Favourites();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GifFavouriteGesture(
              uri: Uri.parse('https://static.klipy.com/media/test.gif'),
              service: service,
              child: const SizedBox(
                width: 200,
                height: 200,
                child: Text('GIF'),
              ),
            ),
          ),
        ),
      );
      final target = find.byType(GifFavouriteGesture);
      await tester.tap(target);
      await tester.pump();
      expect(service.toggles, 0);
      await tester.drag(target, const Offset(50, 0));
      await tester.pump();
      expect(service.toggles, 0);
      await tester.longPress(target);
      await tester.pump();
      expect(service.toggles, 1);
      expect(find.text('GIF added to favourites.'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
      await tester.longPress(target);
      await tester.pump();
      expect(service.toggles, 2);
    },
  );
  testWidgets('non-provider images do not expose favourite gestures', (
    tester,
  ) async {
    final service = Favourites();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GifFavouriteGesture(
          uri: Uri.parse('https://example.test/private.gif'),
          service: service,
          child: const Text('Image'),
        ),
      ),
    );
    await tester.longPress(find.text('Image'));
    expect(service.toggles, 0);
  });
}
