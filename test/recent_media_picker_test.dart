import 'package:deltiecord/ui/mobile/mobile_attachment_picker.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Recent queries all accessible media, not an album', (
    tester,
  ) async {
    const channel = MethodChannel('com.fluttercandies/photo_manager');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'requestPermissionExtend') return 3;
      return {'data': <Object>[]};
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.regular)],
        ),
        home: const Scaffold(body: MobileAttachmentPicker()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent photos and videos'), findsOneWidget);
    expect(calls.any((call) => call.method == 'getAssetPathList'), false);
    final query = calls
        .where((call) => call.method == 'getAssetsByRange')
        .single;
    expect(query.arguments['start'], 0);
    expect(query.arguments['end'], 60);
    expect(query.arguments.containsKey('id'), false);
  });
}
