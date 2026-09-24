import 'package:deltiecord/models/forum_post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forum metadata is declarative, bounded and round-trips', () {
    final post = ForumPost.validated(' A topic ', [
      'help',
      ' help ',
      '',
      'support',
    ]);
    expect(post.title, 'A topic');
    expect(post.tags, ['help', 'support']);
    expect(ForumPost.fromJson(post.toJson())!.tags, post.tags);
    expect(ForumPost.fromJson({'title': 7}), isNull);
    expect(ForumPost.fromJson({'title': '', 'execute': 'ignored'}), isNull);
    expect(() => ForumPost.validated('x' * 121, []), throwsFormatException);
    expect(
      () => ForumPost.validated('title', List.generate(6, (i) => '$i')),
      throwsFormatException,
    );
    expect(ForumPost.validated('👩🏽‍💻' * 120, []).title, isNotEmpty);
  });
}
