/// SeND upload-batch metadata. This lives inside ordinary encrypted content.
class MediaGalleryMembership {
  const MediaGalleryMembership({
    required this.id,
    required this.index,
    required this.count,
  });
  static const contentKey = 'net.deltie.send.gallery';
  static const maximumItems = 50;
  final String id;
  final int index;
  final int count;
  bool get isValid =>
      id.length >= 16 &&
      id.length <= 96 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) &&
      count > 0 &&
      count <= maximumItems &&
      index >= 0 &&
      index < count;

  static MediaGalleryMembership? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'], index = value['index'], count = value['count'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{16,96}$').hasMatch(id) ||
        index is! int ||
        count is! int ||
        count < 1 ||
        count > maximumItems ||
        index < 0 ||
        index >= count) {
      return null;
    }
    return MediaGalleryMembership(id: id, index: index, count: count);
  }

  Map<String, Object> toJson() => {'id': id, 'index': index, 'count': count};
}
