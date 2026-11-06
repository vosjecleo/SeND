import 'dart:convert';
import 'dart:math';
import '../models/chat_models.dart';
import 'image_animation.dart';
import 'raw_image.dart';

String newMediaGalleryId() => base64UrlEncode(
  List.generate(24, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');

bool galleryDraftEligible(AttachmentDraft draft) =>
    !isRawImageFile(draft.name, draft.mimeType) &&
    draft.gifSource == null &&
    (draft.mimeType.startsWith('video/') ||
        (draft.mimeType.startsWith('image/') &&
            !hasAnimatedImageHeader(draft.bytes)));

/// Each submission is distinct. Remaining drafts from a partial send retain
/// their original membership so retrying fills that gallery instead of a new one.
List<AttachmentDraft> assignMediaGallery(List<AttachmentDraft> drafts) {
  final fresh = <int>[
    for (var i = 0; i < drafts.length; i++)
      if (galleryDraftEligible(drafts[i]) && drafts[i].gallery == null) i,
  ];
  if (fresh.isEmpty) return drafts;
  if (fresh.length > MediaGalleryMembership.maximumItems) {
    throw StateError('Too many attachments in one gallery.');
  }
  final id = newMediaGalleryId();
  final members = {for (final entry in fresh.indexed) entry.$2: entry.$1};
  return [
    for (final entry in drafts.indexed)
      members.containsKey(entry.$1)
          ? entry.$2.copyWith(
              gallery: MediaGalleryMembership(
                id: id,
                index: members[entry.$1]!,
                count: fresh.length,
              ),
            )
          : entry.$2,
  ];
}
