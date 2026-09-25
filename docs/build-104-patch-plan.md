# SeND 0.9.32+104 — proposed changelog and acceptance plan

> Historical record: observations, plans and validation below apply to the named
> build/date. For the current 0.9.34+106 milestone, see the [documentation index](README.md)
> and [1.0 hardening checklist](RELEASE_READINESS.md). Open validation items are
> not automatically resolved by a later release.

Status: implementation and source push completed. The user subsequently approved
CI builds for all platforms, latest-channel publication and the hosted PWA update.
Baseline is build 103. The changelog records implemented scope; acceptance tests
below include device checks that remain pending, not claims of completed checks.

## Implementation handoff

Source validation (2026-09-24): Flutter analysis clean; full Flutter suite
315 passed, 1 existing skip; Dart formatting, git whitespace checks and shell
syntax checks for changed packaging scripts passed. No platform release build
or CI release job was run. Android concurrency checks are source guards, not a
substitute for the device scenarios below.

- Voice capture uses the record plugin and the existing Matrix attachment path.
  Linux requires `parecord`/`pactl` and `ffmpeg` (package dependencies updated).
  Browsers require HTTPS and microphone permission; codec availability is checked
  and the actual container is identified before upload. No transcription upload.
- Native unsent files live in private temporary directories; browser recordings
  use revocable local blob URLs. Normal discard/send/disposal cleans them up.
  A crash can leave native temporary files for OS cache cleanup; do not claim
  secure erasure. Recordings are not retained across room changes or app restart.
- The ten-minute cap bounds active recording time. The 16 MiB compressed-byte
  check occurs at stop, before materializing bytes/upload; browser recording
  buffers are managed by MediaRecorder until stop.
- Test real Android/background permission interruptions, Windows/Linux capture,
  Safari/PWA codecs and playback, and encrypted interoperability with another
  Matrix client after compilation. Visually verify platform emoji fonts and
  scaled/RTL receipt layout. Native notification race tests need a real device.

## 1. Receipt placement and appearance

- Reduce the 12px check glyph to a proposed 10 logical pixels. Use a dedicated
  subdued palette colour: darker than message text on dark backgrounds, lighter
  than message text on light backgrounds, while retaining accessible contrast.
  Keep a larger invisible hit target and reader tooltip/sheet.
- Text receipts stay immediately after text. Place sticker/media-only receipts
  just to the right of the actual visible media bounds, aligned near the bottom,
  not in a separate row underneath or at the full room width. Reserve their
  width and use a safe trailing wrap only when there truly is no room.
- Apply to captions, polls and albums without losing receipt frontiers on
  hidden album events. Preserve pending/failed-send states and actual SDK edit
  acknowledgement semantics. Edited labels remain in the trailing metadata.
- Tests: text/media/stickers/albums; long captions; RTL; scaled text; frontier
  movement and group readers; all four themes.

## 2. Notification dismissal and cadence

- Existing Android MainActivity.onResume already resets global alert cadence;
  clearRoom already clears history and invalidates room alert state. Fix missed
  calls and publish races rather than adding an independent cooldown timer.
- Reconcile the genuinely visible conversation on foreground/resume, even if
  room ID and visibility did not change. Clear that room's notifications and
  end its alert burst on room open and notification navigation too.
- Separate dismissal from read-marker advancement: scrolling in older history
  must not falsely mark newer messages read. Do not clear unrelated rooms.
- Check foreground/room generation immediately before queued workers publish,
  so a completed background fetch cannot recreate a dismissed notification.
- Tests: reopen with same chat selected, open another chat, queued worker races,
  swipe dismissal, background within five minutes, and next-message vibration.

## 3. Appearance selection and live updates

- Replace forced equal-width theme tiles with one compact Theme selector row,
  displaying the selected name and a small palette swatch.
- Open a themed chooser with four one-line radio choices: Light, Gray, Dark,
  Night. Each has a small preview swatch; selection applies and closes it.
  Desktop uses a compact popup/dialog; mobile a centered, scroll-safe chooser.
  No mandatory 2x2 grid, clipped labels or horizontally hidden options.
- Trace local preference assignment, account-data echoes, notifier delivery,
  cached MaterialApp and already-open route themes. Current setters already
  notify; resume forcibly invalidates the root configuration cache. This is
  evidence of a propagation/cache candidate, not a proven root cause yet.
- Ensure appearance changes propagate immediately through an explicit reliable
  preference update path; cache expensive theme calculations, not stale live
  configuration. Keep local edits from being overwritten by older sync echoes.
  Do not use resume as the normal mechanism for applying settings.
- Tests: repeated foreground changes without resume, settings/chooser still
  open, offline changes, rapid slider changes, late sync echoes, and repeated
  freeze/unfreeze. Test narrow displays and large text.

## 4. Composer and picker polish

- Investigate the mobile send InkResponse/Material interaction as the candidate
  for the white wave. Constrain touch feedback to the send control and theme its
  overlay, retaining tap semantics, accessibility and hold-to-schedule for text.
- Remove the GIF Favourites Card/background, retaining a freestanding category
  header and its own content section before Trending. Fullscreen favourite
  controls remain unchanged.

## 5. Consistent Unicode emoji rendering

- Compare the same exact code points in composer, timeline, picker, reactions
  and jumbo-emoji messages. Linux has Noto Color Emoji installed, while current
  picker/timeline styles provide no explicit colour-emoji face.
- Centralize emoji-only typography and choose the available platform colour
  font consistently. Prevent inherited text-face/weight from selecting outline
  glyphs. Audit text/emoji presentation selectors and preserve skin-tone/ZWJ
  sequences. Do not silently rewrite message content or apply emoji fonts to
  ordinary text, punctuation and digits.
- Verify a real Linux rendering capture, plus Windows/Android/browser fallback.
  Do not blindly reintroduce the previously broken bundled font.
- Exported review file: /home/cleo/Documents/SeND-0.9.32-104-emoji-alias-review.txt
  Includes all 1,913 static catalogue entries; account-specific custom packs
  are not part of that dataset. Current main alias is the first merged keyword,
  not an explicit primary field. Export includes proposal columns; alias changes
  will follow the user's edits, not be invented during this patch.

## 6. Voice-message recorder

- Reuse the existing AttachmentDraft voiceMessage/duration/waveform and SDK
  sendVoiceMessage upload/encryption path. No separate messaging protocol.
- Show microphone instead of Send only when draft is empty and there are no
  attachments or active edit. A reply may be preserved for a voice message.
- Tap microphone to request permission and begin recording. Replace composer
  text with elapsed time and actual, scrolling amplitude bars; replace Emoji
  with Pause, and microphone with square Stop. Pause toggles to Resume; timer
  and amplitude history stop advancing while paused.
- Stop creates a reviewable draft with playback, Delete and Send. It does not
  immediately transmit the audio. Cancel/delete releases the microphone and
  removes temporary audio. Explicit Send uploads exactly once.
- Proposed initial bounds: ten minutes and 16 MiB, also respecting homeserver
  upload limits. Bound waveform memory/repaint area; do not rebuild the timeline
  for every amplitude sample. Reduced motion disables decorative scrolling,
  while retaining functional level/time information.
- Use a cross-platform recorder with pause/resume and amplitude support. The
  record package supports these APIs, but encoder/container selection must be
  capability-tested per platform. Prefer interoperable compressed audio; never
  relabel bytes as a different codec. Safari/browser recording requires runtime
  permission/codec checks and hands-on validation.
- Pause/stop safely on app background, microphone interruption or room change;
  never silently record across rooms or while a call owns the microphone.
  Stop device/browser tracks on every exit path. Private native temporary files,
  bounded browser blobs, cleanup on discard/logout, retained draft on send error.
- Test denied permissions, missing microphone, pause/resume, playback/send,
  interruption, size/time bounds, encryption and another Matrix client's playback.

## 7. Speech-to-text exploration (not an implicit server deployment)

- Recommended experiment: optional self-hosted transcription service using
  faster-whisper (CPU/GPU) or whisper.cpp (CPU-friendly/native option). Benchmark
  Dutch and English samples on available hardware before choosing a model.
- Possible UX: explicit Transcribe on a voice message, or dictation into an
  editable composer draft. Neither should auto-send inferred text.
- Matrix homeservers cannot automatically read E2EE audio. Server transcription
  requires explicit opt-in upload of decrypted audio and a clear privacy notice;
  never expose Matrix tokens/keys to the transcriber or promise E2EE through it.
- Authenticate callers, allow only bounded uploaded audio (no arbitrary URL
  fetcher), enforce decoded-duration/byte/CPU limits, per-user quotas, bounded
  queues and concurrency, no content logs, and prompt temporary-data deletion.
- Local inference offers stronger privacy but adds model download, CPU/memory
  and mobile battery cost. Browser SpeechRecognition is not a universal fallback:
  support is limited and some implementations use external servers.
- Implementation/server enablement requires a separate choice after benchmarks;
  the voice recorder does not depend on transcription.

References inspected:
- https://support.discord.com/hc/en-us/articles/13091096725527-Voice-Messages
- https://pub.dev/packages/record
- https://github.com/SYSTRAN/faster-whisper
- https://github.com/ggml-org/whisper.cpp/tree/master/examples/server
- https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition

## Delivery / exclusions

Run focused regression tests, Flutter analysis/full tests, native and web CI
builds only once implementation/build is authorized. Device rendering and
recording tests must supplement host widget tests. No unrelated timeline scroll
rewrite. Previously deferred iOS startup/touch-offset/session investigations are
not silently claimed fixed by this plan. No code has been changed for build 104.
