import 'dart:math';
import 'personal_data.dart';

enum SpaceDropPosition { before, inside, after }

class SpaceDragItem {
  const SpaceDragItem.space(this.id, {this.parentFolder}) : isFolder = false;
  const SpaceDragItem.folder(this.id) : isFolder = true, parentFolder = null;
  final String id;
  final bool isFolder;
  final String? parentFolder;
  String get key => '${isFolder ? 'folder' : 'space'}:$id';
}

/// Personal rail layout only. Never writes Matrix membership or hierarchy.
Future<String?> dropSpace(
  PersonalData data,
  List<String> visible,
  SpaceDragItem source,
  SpaceDragItem target,
  SpaceDropPosition position,
) async {
  if (source.key == target.key) return null;
  final order = visible.toSet().toList(), changes = <String, Object?>{};
  String? folder(String id) => changes.containsKey('folderOf:$id')
      ? changes['folderOf:$id'] as String?
      : data.folderFor(id);
  List<String> members(String id) =>
      order.where((s) => folder(s) == id).toList();
  final moving = source.isFolder ? members(source.id) : [source.id];
  if (moving.isEmpty || moving.any((s) => !order.contains(s))) return null;
  final oldFolder = source.isFolder ? source.id : data.folderFor(source.id);
  var destination = target.isFolder ? target.id : folder(target.id);
  String? expanded;
  List<String> anchor = target.isFolder ? members(target.id) : [target.id];

  if (position == SpaceDropPosition.inside) {
    if (destination == null) {
      if (!order.contains(target.id)) return null;
      destination = source.isFolder
          ? source.id
          : '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
      if (!source.isFolder) changes['folder:$destination'] = 'Folder';
      changes['folderOf:${target.id}'] = destination;
    }
    if (!source.isFolder && destination == oldFolder && !target.isFolder) {
      anchor = [target.id];
    } else {
      anchor = members(destination);
    }
    for (final id in moving) {
      changes['folderOf:$id'] = destination;
    }
    if (source.isFolder && destination != source.id) {
      changes['folder:${source.id}'] = null;
    }
    expanded = destination;
  } else if (!source.isFolder) {
    destination = target.isFolder ? null : target.parentFolder;
    changes['folderOf:${source.id}'] = destination;
  }
  if (oldFolder != null && members(oldFolder).isEmpty) {
    changes['folder:$oldFolder'] = null;
  }
  final original = order.indexWhere((s) => anchor.contains(s));
  order.removeWhere(moving.contains);
  final surviving = anchor.where(order.contains).toList();
  final at = surviving.isEmpty
      ? original.clamp(0, order.length)
      : position == SpaceDropPosition.before
      ? order.indexOf(surviving.first)
      : order.indexOf(surviving.last) + 1;
  order.insertAll(at, moving);
  changes['spaceOrder'] = order;
  await data.setAll(changes);
  return expanded;
}
