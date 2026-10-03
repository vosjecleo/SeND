# 0.9.37+116 — Android video hotfix

## Confirmed code defect

The Dart Android preparation layer staged inputs under `Directory.systemTemp`.
The pinned Flutter engine maps that to Android `Context.getCodeCacheDir()`.
The native Media3 bridge intentionally accepts canonical paths only beneath
`Context.cacheDir`. The staged path therefore failed its private-path check
before the encoder started. A generic mock-channel test missed the mismatch.

Preparation now uses path_provider's `getTemporaryDirectory()`, which selects
the matching application cache. The native path boundary is unchanged. Tests
assert the supplied cache root, source bytes, metadata and staging cleanup.
This does not broaden file access or require server changes.

## Failure and recovery

Compression failures remain visible until the user chooses Retry compression,
Send original or Cancel. The original is never sent automatically. A deliberate
original send still goes through normal attachment upload and room encryption;
it may be much larger and its codec may not play on the recipient's device.
Cancel restores an available draft and does not send the video. Preparation is
serialized; UI remains responsive while native compression runs.

The Android path fix is independent of codec/device support. Long HDR/HEVC
camera recordings, unavailable encoders, storage exhaustion and upload limits
can still fail and now have an explicit recovery path. PWA sends retain their
existing no-transcode policy; desktop compression still requires FFmpeg.

## Validation

- Regression tests cover cache selection/cleanup, rotated metadata, caption and
  spoiler preservation, no silent original fallback, retry and cancellation.
- Static analysis and the full Flutter suite are run before publication.
- Local results: clean analysis, 501 Flutter tests passed (4 skipped), 35 server
  tests, 8 packaging tests and 7 browser-bridge JavaScript tests passed. Version,
  formatting and lockfile checks passed. Browser-device checks remain separate.
- All release artifacts are built by CI and verified before mirror/PWA updates.
- No Android device or exact failing clip was attached during investigation.
  The code-level defect is reproduced in regression coverage, not on hardware.

## Android acceptance checks

1. Attach a short portrait camera clip and send it; verify playback, thumbnail,
   dimensions, caption and spoiler on a second client.
2. Repeat with a longer clip and landscape/rotated footage, including encrypted
   and unencrypted rooms. Check cancellation during preparation and retry.
3. Exercise an unsupported clip or encoder failure. Confirm the visible error,
   each recovery action, and that Send original requires a deliberate choice.
4. Background/resume during preparation; test low free storage and a network
   failure during the later upload. Keep the recovery key; do not clear app data.

For codec-specific reports include device, Android version, clip duration,
resolution, codec and the visible error. Do not include private clips or keys
in a public issue without reviewing their contents first.
