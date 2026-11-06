import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/media_album.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets('collage frame respects ordinary media width, mobile=$mobile', (
      tester,
    ) async {
      final screen = mobile ? const Size(430, 900) : const Size(1440, 1000);
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MediaAlbumGrid(
                  mobile: mobile,
                  messages: [
                    _media('one', DateTime(2026), AttachmentKind.image),
                    _media('two', DateTime(2026), AttachmentKind.image),
                  ],
                  itemBuilder: (_, _) => const ColoredBox(color: Colors.blue),
                ),
              ],
            ),
          ),
        ),
      );
      final frame = tester.getRect(find.byType(ClipRRect));
      expect(frame.width, closeTo(mobile ? 354 : 420, .1));
      expect(frame.left, 0);
      expect(tester.takeException(), isNull);
    });
  }
  test('groups adjacent captionless still media by sender and time', () {
    final now = DateTime.utc(2026, 9, 15, 12);
    final messages = [
      _media('new', now, AttachmentKind.image),
      _media(
        'middle',
        now.subtract(const Duration(minutes: 2)),
        AttachmentKind.video,
      ),
      _media(
        'old',
        now.subtract(const Duration(minutes: 4)),
        AttachmentKind.image,
      ),
    ];
    final index = MediaAlbumIndex.fromNewestFirst(messages);
    expect(index.albums['new']?.map((message) => message.id), [
      'old',
      'middle',
      'new',
    ]);
    expect(index.hiddenMessageIds, {'middle', 'old'});
  });

  test('does not fold GIFs or five-minute gaps', () {
    final now = DateTime.utc(2026, 9, 15, 12);
    final captioned = _media(
      'captioned',
      now,
      AttachmentKind.image,
      caption: 'hello',
    );
    final gif = _media(
      'gif',
      now.subtract(const Duration(minutes: 1)),
      AttachmentKind.image,
      animated: true,
    );
    final late = _media(
      'late',
      now.subtract(const Duration(minutes: 7)),
      AttachmentKind.video,
    );
    final index = MediaAlbumIndex.fromNewestFirst([captioned, gif, late]);
    expect(index.albums, isEmpty);
    expect(index.hiddenMessageIds, isEmpty);
  });
  test('caption introduces a collage without absorbing older pictures', () {
    final now = DateTime.utc(2026, 10, 26, 12);
    final messages = [
      _media('second', now, AttachmentKind.image),
      _media(
        'caption',
        now.subtract(const Duration(seconds: 1)),
        AttachmentKind.image,
        caption: 'Trip',
      ),
      _media(
        'older',
        now.subtract(const Duration(seconds: 10)),
        AttachmentKind.image,
      ),
    ];
    final index = MediaAlbumIndex.fromNewestFirst(messages);
    expect(index.albums['second']!.map((m) => m.id), ['caption', 'second']);
    expect(index.hiddenMessageIds, {'caption'});
  });
}

ChatMessage _media(
  String id,
  DateTime timestamp,
  AttachmentKind kind, {
  String? caption,
  bool animated = false,
}) => ChatMessage(
  id: id,
  sender: 'Alice',
  senderId: '@alice:example.org',
  body: caption ?? '$id.jpg',
  timestamp: timestamp,
  pending: false,
  attachment: ChatAttachment(
    kind: kind,
    name: '$id.jpg',
    mimeType: kind == AttachmentKind.video ? 'video/mp4' : 'image/jpeg',
    size: 100,
    encrypted: true,
    spoiler: false,
    caption: caption,
    animated: animated,
  ),
);
