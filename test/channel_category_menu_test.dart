import 'package:deltiecord/ui/channel_category_menu.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  String? space = '!space';
  final renamed = <String>[];
  final deleted = <String>[];
  bool allowed = true;
  @override
  String? get selectedSpaceId => space;
  @override
  List<ChannelCategorySummary> get selectedSpaceCategories => const [
    ChannelCategorySummary(id: 'cat', name: 'Games', roomIds: ['room']),
  ];
  @override
  bool canManageSpaceChannelLayout(String id) => allowed;
  @override
  Future<void> renameChannelCategory(String id, String name) async =>
      renamed.add(name);
  @override
  Future<void> deleteChannelCategory(String id) async => deleted.add(id);
}

void main() {
  for (final desktop in [false, true]) {
    testWidgets('category rename and confirmed deletion, desktop=$desktop', (
      tester,
    ) async {
      final backend = _Backend();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showChannelCategoryMenu(
                  context,
                  backend,
                  backend.selectedSpaceCategories.first,
                  position: desktop ? const Offset(100, 100) : null,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'New name');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(backend.renamed, ['New name']);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete category'));
      await tester.pumpAndSettle();
      expect(backend.deleted, isEmpty);
      expect(
        find.textContaining('No channels or messages will be deleted'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.deleted, isEmpty);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(backend.deleted, ['cat']);
      expect(tester.takeException(), isNull);
    });
  }
}
