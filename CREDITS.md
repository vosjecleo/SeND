# Credits and acknowledgements

Reviewed for the 0.9.34+106 feature-scope milestone. Credits describe dependency
and reference provenance, not an endorsement or security certification. See the
[documentation index](docs/README.md) for current implementation guides.

Deltiecord is original application code built on open-source libraries and
public services. No third-party client repository has been vendored into this
repository. Where an upstream workflow has been adapted, it is called out
below; where Deltiecord directly uses a package, that package stays an external
dependency under its own license.

## Matrix foundations and client references

- [matrix-dart-sdk](https://github.com/famedly/matrix-dart-sdk) provides the
  Matrix client, sync, room, timeline, E2EE, cross-signing, key-backup, media,
  and MatrixRTC APIs used by the backend. Licensed under AGPL-3.0.
- [FluffyChat](https://github.com/krille-chan/fluffychat) was consulted as a
  reference for how a Flutter Matrix client organizes SDK-backed behavior and
  presents interoperable Matrix features. Licensed under AGPL-3.0.
- [Element](https://github.com/element-hq/element-web) and
  [Element X](https://github.com/element-hq/element-x-android) were consulted
  as behavioral/interoperability references for Matrix rooms, recovery,
  replies, media, and calls. No Element code or assets are included.
- Deltiecord's UnifiedPush lifecycle adapts the architecture demonstrated by
  [Element X's UnifiedPush provider](https://github.com/element-hq/element-x-android/tree/develop/libraries/pushproviders/unifiedpush): correlate asynchronous distributor callbacks with a stable per-account instance, persist rotated endpoints, and reconcile the Matrix pusher only after a valid endpoint arrives. Element X is AGPL-3.0-only or covered by its commercial license; Deltiecord's implementation is independently written for Flutter's platform boundary.
  Its direct Android broadcast-receiver lifecycle also informed Deltiecord's
  process-independent delivery path for notifications received while Flutter
  is stopped.
- [FluffyChat's background push implementation](https://github.com/krille-chan/fluffychat/blob/main/lib/utils/background_push.dart) informed Deltiecord's launch-time pusher reconciliation, custom Matrix-gateway discovery behavior, and privacy-preserving `event_id_only` pusher format. FluffyChat is AGPL-3.0-or-later.
- [FluffyChat's Matrix sticker-pack integration](https://github.com/krille-chan/fluffychat)
  was used as an interoperability reference for the widely deployed
  `im.ponies.user_emotes` and `im.ponies.room_emotes` account-data/state
  formats. Deltiecord's picker and backend are independently implemented on
  matrix-dart-sdk and send standard `m.sticker` events; no FluffyChat source or
  assets are bundled.
- The compact three-column layout was inspired by Discord UX. Deltiecord does
  not use Discord branding, artwork, source, or proprietary assets.

## Feature libraries and services

- [emoji-data](https://github.com/iamcal/emoji-data), by Cal Henderson, supplies
  familiar emoji shortcodes (MIT; pinned revision
  `13ee711e222ea17fe537bfea953c687866f16411`). Its license is included in
  `assets/emoji/SHORTCODES-LICENSE.txt`. Existing catalogue keywords remain.
- [record](https://github.com/llfbandit/record) provides cross-platform microphone
  recording, under the BSD-3-Clause license. Flutter includes dependency notices.

- [Flutter](https://github.com/flutter/flutter) and Dart provide the application
  framework and Linux desktop runtime. Flutter is BSD-3-Clause licensed.
- [flutter-webrtc](https://github.com/flutter-webrtc/flutter-webrtc) provides
  native WebRTC bindings used with matrix-dart-sdk's MatrixRTC implementation.
  Licensed under MIT.
- [media_kit](https://github.com/media-kit/media-kit) provides inline and
  full-window audio/video playback. Licensed under MIT.
- [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart)
  resolves playable YouTube streams only for the user's opted-in direct
  preview modes. Licensed under MIT.
- [super_clipboard](https://github.com/superlistapp/super_native_extensions)
  and [super_drag_and_drop](https://github.com/superlistapp/super_native_extensions)
  provide desktop clipboard image access and native file drag/drop. Licensed
  under MIT.
- [flutter_quill](https://github.com/singerdmx/flutter-quill),
  [vsc_quill_delta_to_html](https://github.com/visual-space/vsc_quill_delta_to_html),
  and [markdown](https://github.com/dart-lang/tools/tree/main/pkgs/markdown)
  provide document editing/serialization and typed-markup parsing.
- [flutter_vodozemac](https://github.com/famedly/dart-vodozemac) and Vodozemac
  provide the cryptographic implementation used through the Matrix SDK.
- [flutter_secure_storage](https://github.com/juliansteenbakker/flutter_secure_storage)
  provides OS-keyring-backed storage for sessions and private configuration.
- [UnifiedPush Android connector](https://codeberg.org/UnifiedPush/android-connector)
  provides the standard distributor integration used for private Android push.
  The connector and its optional embedded FCM distributor are Apache-2.0
  licensed. Deltiecord's configured Matrix gateway
  uses [ntfy](https://github.com/binwiederhier/ntfy), which is Apache-2.0 and
  GPL-2.0 licensed depending on the component; no ntfy server code is bundled.
- [KLIPY](https://docs.klipy.com/) supplies GIF search and trending through its
  API. A rate-limited HTTPS proxy holds the key; neither native binaries nor
  the web bundle contains it. Older [GIPHY](https://developers.giphy.com/)
  favourites retain their original public media URLs.
- [pywebpush](https://github.com/web-push-libs/pywebpush) provides standards-based
  Web Push encryption and VAPID delivery on the optional gateway (MPL-2.0).
- [Telegram's Bot API](https://core.telegram.org/bots/api) supplies metadata
  and media for user-requested public sticker-pack imports. A bounded
  Deltiecord proxy holds the bot credential; no Telegram code or assets are
  bundled or republished by Deltiecord itself. The optional server-side
  animation converter uses [python-lottie](https://gitlab.com/mattbas/python-lottie)
  (AGPL-3.0), [CairoSVG](https://github.com/Kozea/CairoSVG) (LGPL-3.0),
  [Pillow](https://github.com/python-pillow/Pillow) (MIT-CMU), and
  [FFmpeg](https://ffmpeg.org/) under the host build's applicable GPL terms.
- [Jome](https://github.com/eepp/jome) supplies the local Unicode emoji name
  and keyword dataset used for offline emoji search and colon completion.
  Deltiecord vendors only `emojis.json`; Jome is MIT licensed.
- Interface text and colour emoji use platform fonts; release packages no
  longer bundle font files that behaved inconsistently across renderers.
- Notification and call sounds are original creations by VosjeCleo. The
  notification, call-connected and call-disconnected asset slots remain
  independently replaceable.
- [sqflite_sqlcipher](https://github.com/davidmartos96/sqflite_sqlcipher)
  provides SQLCipher-backed Android local database storage (MIT).

Additional Dart and Flutter packages are declared in `pubspec.yaml` and retain
their upstream copyright notices and licenses.

## Linux packaging

- [linuxdeploy](https://github.com/linuxdeploy/linuxdeploy) and its AppImage
  output plugin assemble the portable Linux bundle. Licensed under MIT.
- [AppImage](https://github.com/AppImage/appimagetool) supplies the AppImage
  runtime and final packaging tooling. Licensed under MIT.

Thanks to the Matrix specification authors, SDK maintainers, client developers,
package maintainers, and Deltiecord's hands-on testers:
Yeen, Tecilis and Gabe.

And lastly, thanks to the AI developers at Alibaba cloud for building an LLM capable of doing the work of building the base of this app.

## Aero theme icon pack

The bundled Tango subset is from the Tango Desktop Project, released into the
public domain with version 0.8.90. PNG rasterizations are from
[Nigel Tao's Tango icon library](https://github.com/nigeltao/tango-icon-library-pngs),
commit `0a1564d0861bcca68ced31a5798f8d07c39a19ed`. See
`assets/icons/tango/COPYING` and `SOURCE.md`. No Microsoft icon assets are included.
