import 'package:deltiecord/services/gif_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GIPHY selects animated previews and upgrades saved still previews', () {
    final result = GifSearchResult.fromApi({
      'title': 'Test',
      'images': {
        'fixed_width_still': {
          'url': 'https://media.giphy.com/media/test/200w_s.gif',
        },
        'fixed_width': {'url': 'https://media.giphy.com/media/test/200w.gif'},
        'downsized_medium': {
          'url': 'https://media.giphy.com/media/test/giphy.gif',
        },
      },
    })!;
    expect(result.previewUrl.path, endsWith('/200w.gif'));
    expect(result.shareUrl.path, endsWith('/giphy.gif'));
    final saved = GifSearchResult.fromJson({
      ...result.toJson(),
      'preview_url': 'https://media.giphy.com/media/test/200w_s.gif',
    })!;
    expect(saved.animatedPreviewUrl, saved.shareUrl);
  });
}
