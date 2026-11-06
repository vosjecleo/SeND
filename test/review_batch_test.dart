import 'dart:convert';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/gif_service.dart';
import 'package:deltiecord/services/personal_data.dart';
import 'package:deltiecord/services/unavailable_history.dart';
import 'package:deltiecord/ui/delete_message_group.dart';
import 'package:deltiecord/ui/expression_picker.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/gif_favourite_star.dart';
import 'package:deltiecord/ui/voice_control_island.dart';
import 'package:deltiecord/ui/forward_message_dialog.dart';
import 'package:deltiecord/ui/room_access_dialog.dart';
import 'package:deltiecord/models/space_administration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide RoomSummary;
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
}

class _Client extends Client {
  _Client(http.Client httpClient)
    : super('directory-test', database: _Database(), httpClient: httpClient) {
    homeserver = Uri.parse('https://test.invalid');
  }
  @override
  String get userID => '@me:test';
  @override
  String get bearerToken => 'fixture-token';
}

class _DeletionBackend extends FakeBackend {
  final deleted = <String>[];
  @override
  Future<void> redactMessage(String id) async {
    deleted.add(id);
  }
}

class _PermissionBackend extends FakeBackend {
  bool allowed = false;
  @override
  bool canCreateSpaceRoom(String spaceId) => allowed;
}

class _DirectoryBackend extends FakeBackend {
  _DirectoryBackend(this.persist);
  final bool persist;
  bool directory = false;
  @override
  Future<RoomAccessSettings> getRoomAccessSettings(String id) async =>
      RoomAccessSettings(
        roomId: id,
        joinRule: 'invite',
        historyVisibility: 'shared',
        discoverable: directory,
        canEditAccess: true,
        canEditHistory: false,
        canEditPolicy: false,
        roomVersion: '11',
      );
  @override
  Future<void> setRoomDiscoverable(String id, bool value) async {
    if (persist) {
      directory = value;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final persist in [true, false]) {
    testWidgets(
      'directory save verifies persistence before closing, serverKeeps=$persist',
      (tester) async {
        final backend = _DirectoryBackend(persist);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showRoomAccessDialog(context, backend, 'room'),
                  child: const Text('Open access'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open access'));
        await tester.pumpAndSettle();
        final listing = find.widgetWithText(
          SwitchListTile,
          'List in the public room directory',
        );
        await tester.ensureVisible(listing);
        await tester.tap(listing);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        if (persist) {
          expect(find.byType(AlertDialog), findsNothing);
          await tester.tap(find.text('Open access'));
          await tester.pumpAndSettle();
          expect(tester.widget<SwitchListTile>(listing).value, true);
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(
            find.text(
              'The server did not keep the directory setting. Check your permissions and try again.',
            ),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final mobile in [false, true]) {
    testWidgets('room creation entry follows permissions, mobile=$mobile', (
      tester,
    ) async {
      final backend = _PermissionBackend()
        ..currentStatus = SessionStatus.signedIn
        ..spaceList = const [
          SpaceSummary(id: 'space', name: 'Permission server'),
        ]
        ..currentSpaceId = 'space';
      if (mobile) {
        await pumpMobile(tester, backend);
      } else {
        await tester.pumpWidget(DeltiecordApp(backend: backend));
      }
      await tester.pumpAndSettle();
      final add = find.byTooltip(mobile ? 'Create a room' : 'Create room');
      expect(add, findsNothing);
      backend.allowed = true;
      backend.notifyListeners();
      await tester.pumpAndSettle();
      expect(add, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('forward destination identifies its server and shows an avatar', (
    tester,
  ) async {
    const room = RoomSummary(
      id: 'channel',
      name: 'General',
      lastMessage: '',
      unreadCount: 0,
      usesChannelIcon: true,
    );
    final backend = FakeBackend()
      ..roomList = [room]
      ..spaceList = const [SpaceSummary(id: 'space', name: 'Test server')]
      ..currentSpaceId = 'space';
    final message = ChatMessage(
      id: 'message',
      sender: 'Someone',
      body: 'Forward me',
      timestamp: DateTime(2026),
      pending: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showForwardMessageDialog(context, backend, [
                message,
              ], sourceRoomId: 'source'),
              child: const Text('Open forward'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open forward'));
    await tester.pumpAndSettle();
    expect(find.text('General · Test server'), findsOneWidget);
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.leading, isNotNull);
    final title = tile.title! as Text;
    final server = (title.textSpan! as TextSpan).children!.last as TextSpan;
    expect(server.style!.fontStyle, FontStyle.italic);
    expect(server.style!.fontSize, 12);
    await tester.pumpWidget(const SizedBox());
  });
  for (final mobile in [false, true]) {
    testWidgets(
      'another recipient mention does not highlight this user, mobile=$mobile',
      (tester) async {
        const room = RoomSummary(
          id: 'room',
          name: 'Other mention',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        );
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = [room]
          ..messageList = [
            ChatMessage(
              id: 'other-ping',
              sender: 'Friend',
              senderId: '@friend:test',
              body: 'Hi @friend:test',
              timestamp: DateTime(2026),
              pending: false,
              hasVisualMention: true,
              pingedCurrentUser: false,
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
        }
        await tester.tap(find.text(room.name));
        await tester.pumpAndSettle();
        final row = find.byKey(
          mobile
              ? const ValueKey('swipe-other-ping')
              : const Key('message-row-other-ping'),
        );
        expect(row, findsOneWidget);
        if (mobile) {
          expect(
            find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).border is Border &&
                    ((w.decoration as BoxDecoration).border as Border)
                            .left
                            .width ==
                        3,
              ),
            ),
            findsNothing,
          );
        } else {
          final decoration =
              tester.widget<AnimatedContainer>(row).foregroundDecoration
                  as BoxDecoration;
          expect((decoration.border as Border?)?.left.width ?? 0, 0);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('favourite star toggles and reflects changes from another view', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final account = PersonalData(account: '@star:test', write: (_, _) async {});
    await account.open({});
    addTearDown(account.close);
    GifService.bind(account);
    addTearDown(() => GifService.bind(null));
    final gifs = GifService();
    addTearDown(gifs.dispose);
    final gif = GifSearchResult(
      title: 'GIF',
      previewUrl: Uri.parse('https://static.klipy.com/star.gif'),
      shareUrl: Uri.parse('https://static.klipy.com/star.gif'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GifFavouriteStar(gif: gif, service: gifs),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    await tester.tap(find.byTooltip('Favourite GIF'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.star)).color,
      const Color(0xffffb300),
    );
    await gifs.toggleFavorite(gif);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await account.flush();
    await account.close();
  });
  test('directory visibility reads are authenticated and round trip', () async {
    var visibility = 'private';
    var authenticatedReads = 0;
    final client = _Client(
      MockClient((request) async {
        if (request.url.path.contains('/directory/list/')) {
          if (request.method == 'PUT') {
            visibility = jsonDecode(request.body)['visibility'] as String;
          }
          if (request.method == 'GET') {
            expect(request.headers['authorization'], 'Bearer fixture-token');
            authenticatedReads++;
          }
          return http.Response(jsonEncode({'visibility': visibility}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    client.rooms = [
      Room(id: '!room:test', client: client, membership: Membership.join),
    ];
    final backend = MatrixBackend(client: client);
    addTearDown(backend.dispose);
    expect(
      (await backend.getRoomAccessSettings('!room:test')).discoverable,
      false,
    );
    await backend.setRoomDiscoverable('!room:test', true);
    expect(
      (await backend.getRoomAccessSettings('!room:test')).discoverable,
      true,
    );
    await backend.setRoomDiscoverable('!room:test', false);
    expect(
      (await backend.getRoomAccessSettings('!room:test')).discoverable,
      false,
    );
    expect(authenticatedReads, 3);
  });
  testWidgets(
    'call tiles retain their size and centre after a participant leaves',
    (tester) async {
      Future<void> show(int count) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: CompactVoiceGrid(
                itemCount: count,
                itemBuilder: (_, i) =>
                    ColoredBox(key: ValueKey('person-$i'), color: Colors.blue),
              ),
            ),
          ),
        ),
      );
      await show(2);
      final before = tester.getRect(find.byKey(const ValueKey('person-0')));
      await show(1);
      final after = tester.getRect(find.byKey(const ValueKey('person-0')));
      expect(after.size, before.size);
      expect(after.center.dx, closeTo(200, .1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('expression picker stays above keyboard on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    tester.view.padding = const FakeViewPadding(top: 40);
    tester.view.viewPadding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final gifs = GifService();
    addTearDown(gifs.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showExpressionPicker(context, FakeBackend(), gifs),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(BottomSheet));
    final results = tester.getRect(find.text('GIFs'));
    expect(results.top, greaterThanOrEqualTo(40));
    expect(results.bottom, lessThan(520));
    expect(sheet.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'same provider GIF matches favourites across different rendition URLs',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final account = PersonalData(
        account: '@gif:test',
        write: (_, _) async {},
      );
      await account.open({});
      addTearDown(account.close);
      GifService.bind(account);
      addTearDown(() => GifService.bind(null));
      final gifs = GifService();
      addTearDown(gifs.dispose);
      GifSearchResult rendition(String suffix) => GifSearchResult(
        title: 'GIF',
        previewUrl: Uri.parse('https://static.klipy.com/$suffix.gif'),
        shareUrl: Uri.parse('https://static.klipy.com/$suffix.gif'),
        providerId: 'klipy:stable',
      );
      await gifs.toggleFavorite(rendition('small'));
      expect(gifs.isFavorite(rendition('large')), true);
      await gifs.toggleFavorite(rendition('large'));
      expect(await gifs.favorites(), isEmpty);
    },
  );
  for (final count in [1, 2]) {
    testWidgets(
      'gallery deletion is all or nothing before confirmation, loaded=$count',
      (tester) async {
        final backend = _DeletionBackend();
        final group = [
          for (var i = 0; i < count; i++)
            ChatMessage(
              id: 'image-$i',
              sender: 'Me',
              body: '',
              timestamp: DateTime(2026),
              pending: false,
              own: true,
              attachment: ChatAttachment(
                kind: AttachmentKind.image,
                name: 'photo.png',
                mimeType: 'image/png',
                size: 1,
                encrypted: true,
                spoiler: false,
                gallery: MediaGalleryMembership(
                  id: 'abcdefghijklmnop',
                  index: i,
                  count: 2,
                ),
              ),
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => deleteMessageGroup(context, backend, group),
                  child: const Text('Delete gallery'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Delete gallery'));
        await tester.pumpAndSettle();
        if (count == 1) {
          expect(
            find.text('Load the whole gallery before deleting it.'),
            findsOneWidget,
          );
          expect(backend.deleted, isEmpty);
        } else {
          expect(backend.deleted, isEmpty);
          await tester.tap(find.text('Delete').last);
          await tester.pumpAndSettle();
          expect(backend.deleted, ['image-0', 'image-1']);
        }
      },
    );
  }
  test(
    'undecryptable runs after state messages collapse without hiding plaintext',
    () {
      final messages = [
        for (var i = 0; i < 6; i++)
          ChatMessage(
            id: '$i',
            sender: 'User',
            body: 'Body $i',
            timestamp: DateTime(2026),
            pending: false,
          ),
      ];
      final result = collapseUnavailableHistory(messages, {'1', '2', '4', '5'});
      expect(result.map((m) => m.id), ['0', '1', '3', '4']);
      expect(result[0], same(messages[0]));
      expect(result[2], same(messages[3]));
      expect(result[1].system, true);
      expect(result[3].system, true);
      expect(messages, hasLength(6));
    },
  );
}
