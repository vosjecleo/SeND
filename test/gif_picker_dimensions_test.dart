import 'dart:convert';
import 'dart:typed_data';
import 'package:deltiecord/services/gif_service.dart';
import 'package:deltiecord/ui/giphy_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gifs extends GifService {
  final requests = <int>[];
  final _categories = <String, Future<List<GifSearchResult>>>{};
  @override
  Future<List<GifSearchResult>> categoryLinks(String query) =>
      _categories.putIfAbsent(
        query,
        () async => (await page(query: query)).items.take(5).toList(),
      );
  bool failOnce = false;
  List<GifSearchResult> items(int page, [int count = 2]) => [
    for (var i = 0; i < count; i++)
      GifSearchResult(
        title: 'Test',
        previewUrl: Uri.parse('https://static.klipy.com/p$page-$i.gif'),
        shareUrl: Uri.parse('https://static.klipy.com/p$page-$i.gif'),
        width: 100,
        height: count == 2 ? (i == 0 ? 50 : 200) : 100,
      ),
  ];
  @override
  List<GifSearchResult> get frequent => items(1);
  @override
  Future<List<GifSearchResult>> favorites() async => items(1);
  @override
  Future<GifSearchPage> page({String query = '', int page = 1}) async {
    requests.add(page);
    if (failOnce) {
      failOnce = false;
      throw StateError('Synthetic network outage');
    }
    return GifSearchPage(
      items: items(page, 24),
      page: page,
      hasMore: page == 1,
    );
  }

  @override
  Future<Uint8List> preview(GifSearchResult gif) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
}

void main() {
  for (final width in [360.0, 620.0]) {
    testWidgets(
      'GIF home and uncropped variable-height favourites at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = _Gifs();
        addTearDown(service.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GiphyDialog(
                service: service,
                embedded: true,
                autoplay: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('gif-home')), findsOneWidget);
        expect(
          tester
              .getTopLeft(
                find
                    .ancestor(
                      of: find.text('Favourites'),
                      matching: find.byType(InkWell),
                    )
                    .first,
              )
              .dy,
          closeTo(
            tester
                .getTopLeft(
                  find
                      .ancestor(
                        of: find.text('Frequently used'),
                        matching: find.byType(InkWell),
                      )
                      .first,
                )
                .dy,
            .1,
          ),
        );
        expect(
          tester.getTopLeft(find.text('Trending')).dy,
          greaterThan(tester.getTopLeft(find.text('Favourites')).dy),
        );
        expect(find.byIcon(Icons.gif_box_outlined), findsNothing);
        expect(find.byIcon(Icons.trending_up), findsNothing);
        expect(find.byIcon(Icons.favorite), findsOneWidget);
        expect(find.byIcon(Icons.history), findsOneWidget);
        expect(
          service.requests,
          isNotEmpty,
        ); // Category covers use provider results; local categories stay local.
        await tester.tap(find.text('Favourites'));
        await tester.pumpAndSettle();
        final first = tester.getSize(
          find.byKey(ValueKey(service.items(1)[0].shareUrl)),
        );
        final second = tester.getSize(
          find.byKey(ValueKey(service.items(1)[1].shareUrl)),
        );
        expect(first.width, closeTo(second.width, .1));
        expect(first.width / first.height, closeTo(2, .01));
        expect(second.width / second.height, closeTo(.5, .01));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('scrolling fetches the next GIF batch without page buttons', (
    tester,
  ) async {
    final service = _Gifs();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GiphyDialog(service: service, embedded: true, autoplay: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    service.requests.clear();
    await tester.tap(find.text('Trending'));
    await tester.pumpAndSettle();
    expect(service.requests, [1]);
    final results = find.byKey(const ValueKey('gif-results-trending'));
    // At this wide viewport 24 square tiles span several screens.
    for (var i = 0; i < 12 && service.requests.length == 1; i++) {
      await tester.drag(results, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(service.requests, [1, 2]);
    expect(find.text('Next page'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a failed batch can retry without skipping the cursor', (
    tester,
  ) async {
    final service = _Gifs();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GiphyDialog(service: service, embedded: true, autoplay: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    service.requests.clear();
    service.failOnce = true;
    await tester.tap(find.text('Trending'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(service.requests, [1, 1]);
  });
}
