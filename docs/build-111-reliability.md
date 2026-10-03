# SeND 0.9.36+111 — reliability pass

> Historical release/investigation record. Versions, observations and validation
> below apply to that build, not necessarily the latest release. See the
> [current guides](README.md) and [changelog](../CHANGELOG.md); later releases
> do not automatically close unverified device tests.

Scope and changes are listed in the [changelog](../CHANGELOG.md).

## Implementation boundaries

- GIF playback uses the same bounded decoder in picker, chat and fullscreen.
  Visible-but-unfocused desktop windows now continue decoding. This addresses
  a lifecycle stop condition, not a proven explanation for every Windows GPU
  or codec failure. Explicit autoplay/reduced-motion preferences still apply.
- Windows IPC uses a local, owner-restricted named pipe in a worker isolate.
  It accepts activity updates only; no Discord credentials, join secrets or
  remote control. An existing Discord listener is never displaced.
- Game matching reads local Steam manifests and running processes. On Linux,
  bounded process metadata identifies Proton/GoldSrc games; these process
  paths and environment contents are not uploaded. Unknown/non-Steam software
  can still require a manual activity rule. Artwork has a controller fallback.
- Android Media3 preparation preserves aspect/rotation and produces H.264/AAC
  MP4 at up to 1280 pixels and 30 fps, targeting 20 MiB with a 24 MiB hard cap.
  Long clips that cannot meet the budget require trimming or original quality.
  Device encoder failure is visible and never silently uploads the original.
  Existing desktop preparation uses FFmpeg; browsers retain original uploads.
- Encrypted video integrity remains mandatory before decryption/playback.
  Large original encrypted videos therefore retain a download/verification wait.
  Raising the PWA cap to 64 MiB does not make unsupported HEVC profiles playable.
- DM/general classification is account-local Matrix `m.direct` data, synchronized
  across that account's clients. It does not make a private room public.

## Validation and remaining device checks

Regression coverage includes GIF frames across lifecycle changes, rich text
height/whitespace, game path matching/ranking, browser image-paste bytes and
room-switch safety, and Android preparation metadata/error handling.
Windows CI runs a real named-pipe round trip and ownership/rebind test;
Android CI compiles the Media3 bridge. Neither substitutes for hardware QA.

Before calling these symptoms resolved on all devices, test:

1. Windows: picker/chat/fullscreen GIFs while focused, unfocused and after restore;
   image paste then send/edit/cancel; system test notification and a real incoming
   message with the selected room minimized; Steam and non-Steam game transitions.
2. Android: portrait/landscape camera clips, long clips, encoder cancellation and
   original-quality fallback; inspect aspect ratio and metadata in another client.
3. iPhone Home Screen PWA: allow notifications from Settings, close the PWA and
   send a message from another account. Repeat after reopening and backgrounding.
   Use push diagnostics if delivery fails; ntfy is not required for Web Push.
   Test Photos image paste through the iOS paste menu on a physical device.
4. Desktop: receive messages during rapid minimize/restore and while no room is
   selected; verify the timeline, typing and receipts refresh without sending.

The selected-room notification gate and resume refresh changes are targeted
fixes, not a claim that every reported sync delay has been reproduced locally.
