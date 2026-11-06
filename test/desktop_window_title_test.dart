import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/desktop_window_title.dart';
import 'package:deltiecord/services/desktop_window_service.dart';
import 'package:deltiecord/version.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prefix = 'SeND v$deltiecordDisplayVersion';
  RoomSummary room(String name, {bool direct = false}) => RoomSummary(
    id: 'room',
    name: name,
    lastMessage: '',
    unreadCount: 0,
    usesChannelIcon: !direct,
    isDirect: direct,
  );
  test('window titles cover Home, DMs and server channels', () {
    expect(desktopWindowTitle(), prefix);
    expect(
      desktopWindowTitle(
        room: room('Alice', direct: true),
        serverName: 'Unrelated server',
      ),
      '$prefix | Alice',
    );
    expect(
      desktopWindowTitle(room: room('General'), serverName: 'Deltie'),
      '$prefix | General - Deltie',
    );
    expect(
      desktopWindowTitle(room: room('Group chat')),
      '$prefix | Group chat',
    );
  });
  test('names remain literal, single-line and bounded', () {
    expect(desktopWindowTitle(room: room('A\nB\x1b')), '$prefix | A B');
    final title = desktopWindowTitle(room: room('🐈' * 200));
    expect(title.runes.length, prefix.runes.length + 3 + 160);
    expect(title, isNot(contains('\uFFFD')));
  });
  test(
    'native title calls are deduplicated and carry plain UTF-8 text',
    () async {
      const channel = MethodChannel('net.deltie.deltiecord/window');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await DesktopWindowService.setTitle('$prefix | 🐈 title-test');
      await DesktopWindowService.setTitle('$prefix | 🐈 title-test');
      expect(calls.length, 1);
      expect(calls.single.method, 'setTitle');
      expect(calls.single.arguments, '$prefix | 🐈 title-test');
    },
  );
}
