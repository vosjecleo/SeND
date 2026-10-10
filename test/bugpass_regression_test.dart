import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/space_administration.dart';
import 'package:deltiecord/services/activity_source_native.dart';
import 'package:deltiecord/services/unavailable_history.dart';
import 'package:deltiecord/ui/inline_composer_preview.dart';
import 'package:deltiecord/ui/rich_message.dart';
import 'package:deltiecord/ui/json_theme.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:deltiecord/ui/video_playback_status.dart';

void main() {
  for (final marker in ['*', '**', '_', '__', '~~', '||']) {
    for (final body in [r'hi\', r'\hi', r'h\i']) {
      test('escape cancels $marker formatting in $body', () {
        final input = '$marker$body$marker';
        final sent = serializePlainComposer(Document()..insert(0, input));
        expect(sent.html, '$marker${body.replaceAll('\\', '')}$marker');
        expect(
          inlineComposerPreview(input, const TextStyle()).toPlainText(),
          input,
        );
        final preview = inlineComposerPreview(input, const TextStyle());
        expect(
          preview.children!.whereType<TextSpan>().every(
            (span) => span.style == null,
          ),
          isTrue,
        );
      });
    }
  }
  test(
    'preview preserves characters, spaces, newlines and muted delimiters',
    () {
      const input = 'a **bold**\n\n ||spoiler||  ';
      final preview = inlineComposerPreview(
        input,
        const TextStyle(color: Colors.white),
      );
      expect(preview.toPlainText(), input);
      final spans = preview.children!.whereType<TextSpan>();
      expect(
        spans.firstWhere((span) => span.text == 'bold').style!.fontWeight,
        FontWeight.bold,
      );
      expect(spans.firstWhere((span) => span.text == '**').style!.color!.a, .5);
    },
  );
  test(
    'retired Aero preferences fall back, custom glass themes still work',
    () {
      final source = File('assets/themes/aero.json').readAsStringSync();
      expect(
        JsonTheme.fromPreferences(AppPreferences(themeJson: source)),
        isNull,
      );
      expect(
        JsonTheme.fromPreferences(
          AppPreferences(
            themeJson: source.replaceAll('deltiecord.aero', 'custom.glass'),
          ),
        ),
        isNotNull,
      );
    },
  );
  test('role mentions notify only assigned members of this room', () {
    const roles = SpaceRoles(
      roles: [SpaceRole(id: 'mods', name: 'Mod Team', powerLevel: 50)],
      members: {
        '@me:test': {'mods'},
        '@in:test': {'mods'},
        '@elsewhere:test': {'mods'},
        '@plain:test': {},
      },
    );
    const room = {'@me:test', '@in:test', '@plain:test'};
    expect(roles.mentionedMembers('hi @Mod Team!', room, exclude: '@me:test'), {
      '@in:test',
    });
    expect(roles.mentionedMembers('@Mod Teamster', room), isEmpty);
    expect(roles.mentionedMembers('@Mod Team:example.org', room), isEmpty);
  });
  test('unavailable history collapse is presentation-only and recoverable', () {
    final messages = [
      for (var i = 0; i < 4; i++)
        ChatMessage(
          id: '$i',
          sender: 'User',
          body: 'Unable to decrypt this message',
          timestamp: DateTime(2026, 1, i + 1),
          pending: false,
        ),
    ];
    final collapsed = collapseUnavailableHistory(messages, {'0', '1'});
    expect(collapsed.length, 3);
    expect(collapsed.first.system, isTrue);
    expect(collapsed.first.body, contains('2 earlier messages'));
    expect(collapsed[1], same(messages[2]));
    expect(collapseUnavailableHistory(messages, {}), same(messages));
    expect(messages.length, 4);
  });
  test('large encrypted videos get a bounded longer startup allowance', () {
    expect(videoStartupTimeout(null), const Duration(seconds: 60));
    expect(
      videoStartupTimeout(100 * 1024 * 1024),
      const Duration(seconds: 260),
    );
    expect(
      videoStartupTimeout(1024 * 1024 * 1024),
      const Duration(minutes: 10),
    );
  });
  test(
    'Minecraft detection requires its client main class, not a launcher',
    () {
      expect(
        isMinecraftClientArguments(['java', 'net.minecraft.client.main.Main']),
        isTrue,
      );
      expect(
        isMinecraftClientArguments([
          'java',
          'net.fabricmc.loader.impl.launch.knot.KnotClient',
        ]),
        isTrue,
      );
      expect(
        isMinecraftClientArguments(['java', '-jar', 'minecraft-launcher.jar']),
        isFalse,
      );
    },
  );
  test(
    'local icon lookup supports named raster files and scalable SVGs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'send-icon-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/icons/hicolor/scalable/apps/blender.svg';
      await File(path).parent.create(recursive: true);
      await File(path).writeAsString('<svg/>');
      expect(findLocalActivityIcon('blender', [directory.path]), path);
      expect(findLocalActivityIcon('../secret', [directory.path]), isNull);
    },
  );
  test(
    'Minecraft asset index resolves existing icon without network access',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'send-minecraft-icon-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final hash = 'aa${List.filled(38, '0').join()}';
      final icon = File('${directory.path}/objects/aa/$hash');
      await icon.parent.create(recursive: true);
      await icon.writeAsBytes(
        File('assets/icons/tango/actions-list-add.png').readAsBytesSync(),
      );
      final index = File('${directory.path}/indexes/test.json');
      await index.parent.create(recursive: true);
      await index.writeAsString(
        jsonEncode({
          'objects': {
            'icons/icon_32x32.png': {'hash': hash},
          },
        }),
      );
      expect(await loadMinecraftActivityIcon(directory.path), isNotNull);
    },
  );
  testWidgets('full Matrix mentions display localpart and keep target link', (
    tester,
  ) async {
    final sent = serializePlainComposer(
      Document()..insert(0, 'Hello @friend:example.org'),
    );
    expect(sent.html, contains('https://matrix.to/#/@friend:example.org'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatrixHtmlText(html: sent.html!, fallback: sent.plainText),
        ),
      ),
    );
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.textSpan!.toPlainText(), 'Hello @friend');
  });
}
