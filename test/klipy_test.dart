import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/gif_service.dart';
import 'package:deltiecord/ui/gif_favourite_button.dart';

void main() {
  Map<String, Object> item({String host = 'static.klipy.com'}) => {
    'type': 'gif',
    'title': 'Test',
    'file': {
      'sm': {
        'gif': {'url': 'https://$host/small.gif', 'size': 1200},
      },
      'md': {
        'gif': {'url': 'https://$host/medium.gif', 'size': 2400},
      },
      'hd': {
        'gif': {'url': 'https://$host/large.gif', 'size': 50000000},
      },
    },
  };
  test(
    'KLIPY selects animated bounded renditions, not blur/still thumbnails',
    () {
      final result = GifSearchResult.fromKlipy(item())!;
      expect(result.previewUrl.path, '/small.gif');
      expect(result.shareUrl.path, '/medium.gif');
      expect(
        GifSearchResult.fromJson(result.toJson())!.shareUrl,
        result.shareUrl,
      );
    },
  );
  test(
    'KLIPY rejects adverts, missing media, and untrusted returned origins',
    () {
      expect(GifSearchResult.fromKlipy({...item(), 'type': 'ad'}), isNull);
      expect(GifSearchResult.fromKlipy({'type': 'gif'}), isNull);
      for (final host in [
        'static.klipy.com.evil.test',
        '127.0.0.1',
        'user@static.klipy.com',
        'static.klipy.com:8080',
      ]) {
        expect(GifSearchResult.fromKlipy(item(host: host)), isNull);
      }
    },
  );
  test(
    'favouriting never accepts credentials, local URLs, or provider lookalikes',
    () {
      for (final value in [
        'http://static.klipy.com/a.gif',
        'https://static.klipy.com.evil/a.gif',
        'https://a:b@static.klipy.com/a.gif',
        'https://static.klipy.com:444/a.gif',
        'mxc://example/a',
      ]) {
        expect(isFavouriteableGifUri(Uri.parse(value)), isFalse);
      }
      expect(
        isFavouriteableGifUri(Uri.parse('https://static.klipy.com/a.gif')),
        isTrue,
      );
      expect(
        isFavouriteableGifUri(Uri.parse('https://media.giphy.com/a.gif')),
        isTrue,
      );
    },
  );
}
