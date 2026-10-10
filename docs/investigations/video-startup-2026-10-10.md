# Video startup and missing posters

Reported samples:

- `SeND.mp4`: 20,568,414 bytes, 119.808 seconds, H.264 High/yuv420p,
  480x360, AAC. Its MP4 index precedes the media data.
- `bt7274_combat_record.mp4`: 9,625,864 bytes, 6.016 seconds,
  H.264 High/yuv420p, 1024x1024, AAC.

Both files decode a frame locally in under half a second. SeND.mp4 has a black
opening lasting 1.9 seconds, so taking frame zero produces a black poster.

## Reproduction

The encrypted range proxy withheld its HTTP response until a complete download
and SHA-256 check finished. MediaKit configures libmpv with a five-second network
timeout. A download taking longer could fail inside the player, causing the
desktop fallback to download the attachment again.

Using SeND.mp4 with a local ciphertext server delivering 1 MiB every 400 ms:

- Opening the proxy directly with libmpv's five-second timeout failed after
  5.281 seconds.
- Preparing and verifying the download first took 8.693 seconds. The subsequent
  libmpv open completed in 0.413 seconds, with one upstream download.
- The combat recording took 4.332 seconds to prepare and 0.483 seconds to open
  under the same throttle.

With an unthrottled local server, preparation took 0.567 and 0.253 seconds,
respectively. Libmpv opened both in under half a second. These checks used the
real AES-CTR range decryptor and attachment hash verification.

A separate authenticated download of an existing 13.9 MB Deltie attachment
completed in 0.884 seconds. That checks the current media route, but does not
measure either reported message's original upload or the reporting devices.

## Changes

The backend prepares verified ciphertext before returning a native playback
source. Concurrent requests to prepare the same proxy entry share its download.
Integrity verification remains mandatory.

Mobile video rows show the uploaded poster in a frame sized from Matrix metadata.
They download the full video after Play instead of opening every visible video
when the timeline renders.

Browser uploads now extract dimensions, duration and a JPEG poster from a local
Blob. They retain the original video. Native and browser posters sample ten
percent into the clip, capped at ten seconds, avoiding this sample's black intro.
Uploads also include the poster's dimensions in standard Matrix metadata.

Old messages retain their original metadata and posters. Retest both examples
in the installed app, then resend them to check the new upload metadata. Windows
and iOS rendering still need device checks; browser probing was tested in Chrome.

## Validation

- Full native Flutter suite: 623 passed, 4 skipped.
- Chrome upload test: passed. It checks dimensions, duration, original bytes,
  caption/spoiler preservation and a red poster after a black opening.
- Android Kotlin compilation: passed.
- Static analysis and formatting: passed.
