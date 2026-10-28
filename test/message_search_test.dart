import 'package:deltiecord/services/message_search.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('member selection matches the exact Matrix ID, including case', () {
    expect(
      matchesMessageSearch(
        body: 'hello',
        sender: 'Alice',
        senderId: '@Alice:test',
        query: 'from:@Alice:test',
      ),
      isTrue,
    );
    expect(
      matchesMessageSearch(
        body: 'hello',
        sender: 'Alice',
        senderId: '@alice:test',
        query: 'from:@Alice:test',
      ),
      isFalse,
    );
  });
  test(
    'rich links are searchable without counting mentions or quoted links',
    () {
      bool matches(String html) => matchesMessageSearch(
        body: 'hello',
        formattedBody: html,
        sender: 'Alice',
        query: 'has:link',
      );
      expect(matches('<a href="https://example.org/page">Website</a>'), isTrue);
      expect(
        matches('<a href="https://matrix.to/#/@alice:test">Alice</a>'),
        isFalse,
      );
      expect(
        matches(
          '<mx-reply><a href="https://example.org">Quoted</a></mx-reply>hello',
        ),
        isFalse,
      );
    },
  );
  test('requires every search term and rejects unrelated context events', () {
    expect(
      matchesMessageSearch(
        body: 'Matrix search now finds the right message',
        sender: 'Alice',
        query: 'right message',
      ),
      isTrue,
    );
    expect(
      matchesMessageSearch(
        body: 'This event merely surrounded the actual result',
        sender: 'Bob',
        query: 'right message',
      ),
      isFalse,
    );
  });

  test('matches sender names without making term matching fuzzy', () {
    expect(
      matchesMessageSearch(
        body: 'hello there',
        sender: 'Avery Morgan',
        query: 'avery hello',
      ),
      isTrue,
    );
  });

  test('supports sender, date, room, and media filters', () {
    const image = ChatAttachment(
      kind: AttachmentKind.image,
      name: 'cat.png',
      mimeType: 'image/png',
      size: 12,
      encrypted: true,
      spoiler: false,
    );
    expect(
      matchesMessageSearch(
        body: 'holiday photo',
        sender: 'Alice',
        senderId: '@alice:example.org',
        roomName: 'Friends',
        timestamp: DateTime.utc(2026, 8, 15),
        attachment: image,
        query:
            'from:alice in:friends after:2026-08-01 '
            'before:2026-09-01 has:image holiday',
      ),
      isTrue,
    );
    expect(
      matchesMessageSearch(
        body: 'holiday photo',
        sender: 'Alice',
        timestamp: DateTime.utc(2026, 8, 15),
        attachment: image,
        query: 'before:2026-08-01 has:image',
      ),
      isFalse,
    );
  });

  test('recognizes link and file filters without a text term', () {
    expect(
      matchesMessageSearch(
        body: 'https://deltie.net/SeND',
        sender: 'Deltie',
        query: 'has:link',
      ),
      isTrue,
    );
    expect(MessageSearchQuery.parse('from:bob has:file').serverTerm, isEmpty);
  });
}
