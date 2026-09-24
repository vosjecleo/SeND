import 'package:deltiecord/services/auth_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final expected = Uri.parse('https://chat.example.org/auth.html?session=one');
  test('accepts state-bound callback without retaining credentials', () {
    final values = validateAuthCallback(
      Uri.parse(
        'https://chat.example.org/auth.html?session=one&state=nonce&code=example',
      ),
      expected,
      'nonce',
    );
    expect(values['code'], 'example');
  });
  test(
    'rejects wrong origin, path, state, duplicate values and provider errors',
    () {
      for (final address in [
        'http://chat.example.org/auth.html?state=nonce',
        'https://evil.example.org/auth.html?state=nonce',
        'https://chat.example.org/other?state=nonce',
        'https://chat.example.org/auth.html?state=other',
        'https://chat.example.org/auth.html?state=nonce&state=nonce',
        'https://chat.example.org/auth.html?state=nonce&code=a&code=b',
        'https://chat.example.org/auth.html?state=nonce&error=denied',
        'https://user@chat.example.org/auth.html?state=nonce',
        'https://chat.example.org/auth.html?session=other&state=nonce',
        'https://chat.example.org/auth.html?session=one&state=nonce#code=hidden',
      ]) {
        expect(
          () => validateAuthCallback(Uri.parse(address), expected, 'nonce'),
          throwsFormatException,
          reason: address,
        );
      }
    },
  );
  test('native callback must use the selected loopback port', () {
    final local = Uri.parse('http://127.0.0.1:54321/auth/nonce');
    expect(
      () => validateAuthCallback(
        Uri.parse('http://127.0.0.1:54322/auth/nonce?state=nonce'),
        local,
        'nonce',
      ),
      throwsFormatException,
    );
  });
}
