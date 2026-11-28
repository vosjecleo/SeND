import 'dart:typed_data';

import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/profile_card.dart';
import 'package:deltiecord/ui/profile_status_editor.dart';
import 'package:deltiecord/ui/matrix_html_text.dart' show CustomEmojiImage;
import 'package:deltiecord/models/user_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

class _StatusBackend extends FakeBackend {
  @override
  String get userId => '@me:test';
  @override
  String get profileStatusMessage => '🍵 Making tea';
  String? savedStatus;

  @override
  Future<void> updateOwnProfileFields({
    String? bio,
    String? pronouns,
    String? timezone,
    String? statusMessage,
    int? profileColor,
    int? profileColorSecondary,
    Uint8List? bannerBytes,
    bool removeBanner = false,
  }) async {
    savedStatus = statusMessage;
  }
}

void main() {
  const customPrefix = '[:party_cat:](mxc://example.org/cat_image)';
  test('custom status emoji keeps its MXC identity and rejects other URLs', () {
    final status = splitProfileStatus('$customPrefix Hello');
    expect(status.text, 'Hello');
    final custom = customProfileStatusEmoji(status.emoji)!;
    expect(custom.id.toString(), 'mxc://example.org/cat_image');
    expect(custom.fallback, ':party_cat:');
    expect(splitProfileStatus(customPrefix).text, isEmpty);
    expect(
      splitProfileStatus('[:cat:](https://example.org/cat) Hello').emoji,
      isNull,
    );
  });

  testWidgets('custom status emoji renders beside activity and on profiles', (
    tester,
  ) async {
    final backend = _PlayingStatusBackend();
    addTearDown(backend.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: ActivityScope(
            backend: backend,
            child: Column(
              children: [
                ActivityStatus(
                  backend: backend,
                  userId: '@friend:test',
                  presence: UserPresence.online,
                  status: '$customPrefix Hello',
                ),
                const SizedBox(
                  width: 380,
                  child: DeltiecordProfileCard(
                    profile: UserProfileSummary(
                      userId: '@friend:test',
                      displayName: 'Friend',
                      presence: UserPresence.online,
                      statusMessage: '$customPrefix Hello',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CustomEmojiImage), findsNWidgets(2));
    final compact = find.byType(ActivityStatus);
    expect(
      find.descendant(of: compact, matching: find.text('Game')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: compact, matching: find.text('Hello')),
      findsNothing,
    );
    expect(find.text(' • '), findsOneWidget);
    expect(find.textContaining('mxc://'), findsNothing);
  });

  test(
    'status separates one Unicode grapheme and supports emoji-only values',
    () {
      expect(splitProfileStatus('👩🏽‍💻 Writing'), (
        emoji: '👩🏽‍💻',
        text: 'Writing',
      ));
      expect(splitProfileStatus('🇳🇱'), (emoji: '🇳🇱', text: ''));
      expect(splitProfileStatus('Hello 🍵'), (emoji: null, text: 'Hello 🍵'));
      expect(joinProfileStatus('🍵', ' Making tea '), '🍵 Making tea');
      expect(joinProfileStatus(null, ''), '');
    },
  );

  for (final useCustom in [false, true]) {
    testWidgets(
      'tap your own bubble and replace it with ${useCustom ? 'a custom' : 'a Unicode'} emoji',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final backend = _StatusBackend()
          ..stickerPackList = [
            StickerPackSummary(
              id: 'cats',
              name: 'Cat pack',
              stickers: [
                StickerSummary(
                  id: 'cat',
                  name: 'party_cat',
                  mxcUri: Uri.parse('mxc://example.org/cat_image'),
                  assetType: StickerAssetType.emoji,
                  packId: 'cats',
                ),
              ],
            ),
          ];
        addTearDown(backend.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
            ),
            home: Scaffold(
              body: ActivityScope(
                backend: backend,
                child: Center(
                  child: SizedBox(
                    width: 380,
                    child: DeltiecordProfileCard(
                      profile: UserProfileSummary(
                        userId: backend.userId,
                        displayName: 'Me',
                        presence: UserPresence.online,
                        statusMessage: backend.profileStatusMessage,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(ProfileStatusBubble));
        await tester.pumpAndSettle();
        expect(find.text('Edit status'), findsOneWidget);
        expect(find.text('Making tea'), findsOneWidget);
        await tester.tap(find.byTooltip('Change status emoji'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove emoji'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Choose status emoji'));
        await tester.pumpAndSettle();
        final search = find.widgetWithText(
          TextField,
          'Search names and aliases',
        );
        await tester.enterText(search, useCustom ? 'party_cat' : 'sunglasses');
        await tester.pumpAndSettle();
        final choice = find.byKey(
          ValueKey(
            'emoji-picker-result-${useCustom ? 'mxc://example.org/cat_image' : '😎'}',
          ),
        );
        await tester.ensureVisible(choice.first);
        await tester.tap(choice.first);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Change status emoji'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          backend.savedStatus,
          useCustom ? '$customPrefix Making tea' : '😎 Making tea',
        );
      },
    );
  }
}

class _PlayingStatusBackend extends FakeBackend {
  @override
  UserActivity? activityFor(String userId) => UserActivity(
    kind: ActivityKind.game,
    name: 'Game',
    expiresAt: DateTime.now().add(const Duration(minutes: 1)),
  );
}
