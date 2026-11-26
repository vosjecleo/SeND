import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_discovery.dart';
import 'package:deltiecord/services/windows_game_catalogue.dart';
import 'package:deltiecord/ui/activity_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const epic = {
    'bIsApplication': true,
    'AppName': 'Example',
    'MainGameAppName': 'Example',
    'DisplayName': 'Example Game',
    'InstallLocation': r'D:\Epic Games\Example',
    'LaunchExecutable': 'Bin/Example.exe',
  };

  test(
    'Epic identifies complete games and excludes DLC and incomplete installs',
    () {
      final index = WindowsGameIndex(parseEpicGameManifest(epic));
      expect(
        index
            .match(r'd:\epic games\example\BIN\example.EXE', window: false)
            ?.name,
        'Example Game',
      );
      expect(
        index.match(
          r'D:\Epic Games\Example\Bin\OtherEdition.exe',
          window: false,
        ),
        isNull,
      );
      expect(
        index
            .match(r'D:\Epic Games\Example\Bin\OtherEdition.exe', window: true)
            ?.name,
        'Example Game',
      );
      expect(
        index.match(
          r'D:\Epic Games\Example Demo\Bin\Example.exe',
          window: true,
        ),
        isNull,
      );
      expect(
        parseEpicGameManifest({...epic, 'MainGameAppName': 'BaseGame'}),
        isEmpty,
      );
      expect(
        parseEpicGameManifest({...epic, 'bIsIncompleteInstall': true}),
        isEmpty,
      );
      expect(
        parseEpicGameManifest({...epic, 'bIsUnrealEngine': true}),
        isEmpty,
      );
      expect(
        parseEpicGameManifest({...epic, 'LaunchExecutable': r'..\Outside.exe'}),
        isEmpty,
      );
    },
  );

  test(
    'GOG and Xbox match a registered game with a nonstandard install drive',
    () {
      for (final source in ['gog', 'xbox']) {
        final value = {
          'source': source,
          'name': 'The Adventure',
          'path': r'"F:\Library\Adventure\Content"',
          'exe': r'F:\Library\Adventure\Content\Adventure.exe',
        };
        final index = WindowsGameIndex(parseWindowsGameRecord(value));
        expect(
          index
              .match(
                r'f:\library\Adventure\Content\adventure.exe',
                window: false,
              )
              ?.name,
          'The Adventure',
        );
        expect(
          parseWindowsGameRecord({...value, 'exe': r'D:\Other\Unexpected.exe'}),
          isEmpty,
        );
        if (source == 'gog') {
          expect(
            parseWindowsGameRecord({...value, 'dependsOn': '101'}),
            isEmpty,
          );
        }
      }
    },
  );

  test(
    'EA, Ubisoft and Battle.net directory records require a real game window',
    () {
      for (final source in ['ea', 'ubisoft', 'battle.net']) {
        final value = {
          'source': source,
          'name': 'A Game',
          'path': r'C:\Games\A Game',
        };
        final index = WindowsGameIndex(parseWindowsGameRecord(value));
        expect(
          index
              .match(r'C:\Games\A Game\Binaries\AGame.exe', window: true)
              ?.name,
          'A Game',
        );
        expect(
          index.match(r'C:\Games\A Game\Binaries\AGame.exe', window: false),
          isNull,
        );
        expect(
          index.match(r'C:\Games\A Game\REDprelauncher.exe', window: true),
          isNull,
        );
        expect(
          index.match(r'C:\Games\A Game\EasyAntiCheat\app.exe', window: true),
          isNull,
        );
        expect(
          parseWindowsGameRecord({...value, 'path': r'C:\Games'}),
          isEmpty,
        );
        expect(
          parseWindowsGameRecord({...value, 'path': r'\\remote\Games'}),
          isEmpty,
        );
        expect(
          parseWindowsGameRecord({...value, 'name': 'Battle.net'}),
          isEmpty,
        );
      }
    },
  );

  test(
    'exact launcher match wins over an enclosing directory, but not a Steam utility',
    () {
      final launcher = parseEpicGameManifest(epic);
      final index = WindowsGameIndex([
        const ActivityCandidate(
          id: 'D:/Epic Games/',
          name: 'Other',
          kind: ActivityKind.game,
        ),
        ...launcher,
      ]);
      expect(
        index
            .match(r'D:\Epic Games\Example\Bin\Example.exe', window: true)
            ?.name,
        'Example Game',
      );
      final utility = WindowsGameIndex([
        const ActivityCandidate(
          id: 'D:/Epic Games/Example/',
          name: 'Wallpaper Engine',
          steamAppId: '431960',
          kind: ActivityKind.application,
        ),
        ...launcher,
      ]).match(r'D:\Epic Games\Example\Bin\Example.exe', window: true)!;
      expect(allowsActivitySharing(utility, null), isFalse);
    },
  );

  test(
    'activity settings explain unknown game, device, privacy and per-app blocks',
    () {
      const game = ActivityCandidate(
        id: 'game',
        name: 'Example',
        kind: ActivityKind.game,
      );
      const unknown = ActivityCandidate(id: 'unknown', name: 'Another game');
      const settings = ActivitySettings(detect: true, share: true);
      String hint(
        ActivityCandidate item,
        ActivitySettings state, {
        bool visible = true,
      }) => activitySharingHint(item, state, presenceVisible: visible);
      expect(
        hint(unknown, settings),
        'Not recognized. Tap to choose how to share.',
      );
      expect(
        hint(game, settings.copyWith(detect: false)),
        'App detection is off',
      );
      expect(
        hint(game, settings.copyWith(share: false)),
        'Activity sharing is off on this device',
      );
      expect(
        hint(game, settings, visible: false),
        'Sharing is paused while your presence is hidden',
      );
      expect(
        hint(
          game,
          settings.copyWith(
            rules: {
              game.id: const ActivityRule(
                name: 'Example',
                kind: ActivityKind.game,
                allowed: false,
              ),
            },
          ),
        ),
        'Sharing is off for this app',
      );
      expect(hint(game, settings), 'Game · Allowed to share');
    },
  );
}
