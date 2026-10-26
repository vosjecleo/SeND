import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/favourite_reactions_store.dart';
import 'package:deltiecord/services/personal_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'one-character completion ranks synced custom usage first, mobile=$mobile',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final personal = PersonalData(
          account: '@me:test',
          write: (_, _) async {},
        );
        await personal.open({
          '${personalDataPrefix}other': {
            'version': 1,
            'values': {},
            'usage': {'emoji:mxc://test/fir_hangry': 100},
          },
        });
        FavouriteReactionsStore.instance.bind(personal);
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = const [
            RoomSummary(
              id: '!r:test',
              name: 'Frequency test',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
            ),
          ]
          ..stickerPackList = [
            StickerPackSummary(
              id: 'pack',
              name: 'Pack',
              stickers: [
                for (final name in ['happy', 'halo', 'hand', 'fir_hangry'])
                  StickerSummary(
                    id: name,
                    name: name,
                    mxcUri: Uri.parse('mxc://test/$name'),
                    assetType: StickerAssetType.emoji,
                  ),
              ],
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
        }
        await tester.tap(find.text('Frequency test'));
        await tester.pumpAndSettle();
        for (final query in [':h', ':ha']) {
          if (mobile) {
            await tester.enterText(
              find.byKey(const ValueKey('mobile-composer-field')),
              query,
            );
          } else {
            await enterComposer(tester, query);
          }
          await tester.pumpAndSettle();
          final first = find.byKey(
            ValueKey(
              mobile
                  ? 'mobile-emoji-completion-0'
                  : 'emoji-completion-result-0',
            ),
          );
          expect(first, findsOneWidget);
          expect(
            find.descendant(
              of: first,
              matching: find.textContaining('fir_hangry', findRichText: true),
            ),
            findsWidgets,
          );
        }
        await tester.pumpWidget(const SizedBox());
        FavouriteReactionsStore.instance.bind(null);
        await personal.close();
      },
    );
  }
}
