# 0.9.42+133 local acceptance record

This records the local inspection builds before publication. Arch and signed
arm64 Android previews were installed over the existing apps, retaining accounts
and data. Android's ABI-specific installer code is 2133. Cleo approved the final
laptop build after the UI-copy rewrite. See the [changelog](../CHANGELOG.md) for
release scope; CI and deployment are separate from these local results.

## Included

- Clipboard toolbar stability, Android search-index opening and bounded history
  downloads from the earlier phone preview.
- DMs-only, DM/group-chat and all-chat search scopes, applied to downloads and
  ongoing indexing. Scope changes confirm removal of excluded local index rows.
- One-shot keyboard recovery after a transient notification-shade transition,
  without a timed hide loop. Gboard and resume still need device confirmation.
- Reply highlighting ignores quoted fallback links and reply-recipient metadata.
- Single-line mobile message avatars are centred against their text block;
  replies and tall media keep their top alignment.
- Cancelled notification workers close owned headless engines in a non-cancellable
  cleanup block. Startup failures also destroy the newly created engine. Sunup
  closed-app delivery still needs a real distributor/device check.
- Visible profile metadata tiers, optional server batching and immutable image
  reference comparison. Offscreen room avatars are no longer eagerly fetched.
- Fullscreen profile images, bounded profile-media reuse and a byte budget for
  shared link-preview images.
- Tapping a pending image opens a fullscreen editor with crop, rotation,
  aspect-ratio lock, markup and quality controls. Desktop sections stay open;
  mobile uses bottom tool icons. Image and video quality follow settings, with
  Balanced as the default. Crop corners have larger hit targets. The eye button
  toggles a spoiler haze without baking it into the uploaded image.
- Marker and highlighter export use the same rounded paths as the preview.
  Animated images keep their animation.
- Pending videos open a fullscreen trim, crop, rotation, mute and quality editor.
  Native exports use high quality or 12 MiB/24 MiB presets. Video editing is not
  available in the PWA; it can still send the unchanged original.
- Files, Links and Media browse history independently of the open timeline, with
  ten results per page and explicit Previous, Next and page-number controls.
  Sparse history scans are bounded per action. Grid previews use thumbnails,
  not full-resolution originals. The From filter opens a room-member dropdown.
- Separate Local storage and Server storage pages. The server page has uploaded
  media categories, remaining allowance and confirmed age/type/source pruning.
- Opt-in encrypted-upload labels and a per-account device-local retry queue.
  Only type/source/reference metadata is shared, not text, filenames or keys.
- The Synapse adapter, PostgreSQL admission guard, guided setup integration and
  existing-stack installer/rollback path. The default original-upload allowance
  is 12 GiB; operators can override it per account.

## Validation

Android clipboard actions and the corrected marker export are user-confirmed.
Sunup notifications have not been device-tested for this preview.

- 809 native Flutter tests passed, four skipped.
- Three Chromium storage tests passed, including a multi-gigabyte quota regression
  that caught a JavaScript bit-shift bound before the final preview rebuild.
- 59 server/helper tests passed.
- Isolated Synapse 1.159.0/PostgreSQL 16 API tests passed for authentication,
  inventory, quota refusal, labels, owner checks, deletion previews/replay,
  recovered allowance, profile batching and browser preflight.
- Separate PostgreSQL concurrency/admission tests passed.
- Linux release linkage and package integrity passed. The Android APK's version,
  arm64 ABI and signing identity were verified against the previous preview.
- Static analysis and whitespace checks passed before packaging.

At the first preview, production Synapse, the PWA and download mirror were
unchanged, and Server storage reported unavailable until module installation.
The API tests used synthetic accounts and isolated containers. The operator
subsequently installed and activated storage on Deltie: the 12 GiB default is
enforced, API access is no longer preview-restricted and deletion is not dry-run.
These settings were checked read-only before publication; no additional server
activation is needed for this release.

## Preview checks

1. Confirm About shows 0.9.42+133. Test clipboard actions with a finger, notification
   shade return, language switching and background/resume with the keyboard open.
2. Check ordinary outgoing replies versus replies addressed to you, short-message
   avatar alignment and unchanged media layout.
3. Tap a pending PNG/JPEG and an animated image. Check fullscreen crop/rotate,
   aspect locks, marker/highlighter, undo/redo, preview, cancel, captions and
   spoilers. Tap a video and test trim, crop, rotate, mute and all quality choices.
4. Test local search scopes, pause/resume and the larger-limit prompt. Downloads
   remain a user action; they do not fetch media files or mark rooms read.
5. Test real closed-app notifications with Sunup. A receiver diagnostic alone is
   not proof of background decryption or notification display. Android Force stop
   is different from swiping the app away.
6. Open Files and Links in a room whose old attachments are outside the current
   timeline. Check ten-item pages, page-number navigation and the From dropdown.

The editor/search follow-up passed 819 native tests, with four skipped, and 61
server/helper tests. Additional checks passed for a real FFmpeg export with trim,
crop, rotation and muting, phone/desktop editor layout and drawing, catalog paging,
rich-link and selected-member filtering tests, and browser index checks. An
isolated account-limited storage preview passed with quota enforcement off and
pruning in dry-run mode. These are local tests, not a live server installation.

The gallery-style editor revision passed 827 native tests, with four skipped,
and clean static analysis. Tests cover settings-backed quality, saved spoilers,
crop drags outside the image boundary and diagonal/translucent stroke pixels
matching the preview renderer.

## Follow-up acceptance

Search text now matches a contiguous, case-insensitive phrase in the message
body, after removing filters. Text results use ten-item pages. Page totals show
`+` while older history remains unsearched. These changes passed 29 targeted
tests, browser-index checks and static analysis before the final laptop build.

WebCodecs video processing now runs in a same-origin worker, with a pinned,
self-hosted Mediabunny dependency for MP4/MOV/WebM parsing and MP4 writing.
Supported clips export as fast-start H.264/AAC MP4. Compatible audio is copied;
unsupported tracks cause an error, not a silent audio drop. Compression uses
the selected 12/24 MiB preset. Browser editing accepts inputs up to 256 MiB,
4K coded/display dimensions and one hour; high-quality edits have a 128 MiB
output cap. Cancellation or backgrounding terminates the worker. The original
draft stays available. Real Chromium exports and Dart/browser adapter tests
passed; a real iOS PWA check is still required. These checks do not establish
physical-device codec support.

Validation for the WebCodecs/retry changes: 836 native tests passed, four skipped;
the browser adapter and real H.264/AAC export checks passed, as did the release
web validation build. The final quota-reopen guard passed the targeted download
tests. Static analysis is clean. These are test builds, not preview installs.

The final inspected laptop build passed 837 native tests, with four skips,
clean static analysis and all 450 UI-copy decisions: 174 rewrites, 43 removals
and 233 unchanged entries. Codecs passed real Chromium export checks after the
copy changes. The generated module worker uses `.js` for nginx MIME compatibility.

History downloads now retain failed event IDs, rooms, senders and timestamps
in their local checkpoint. Review is paginated, and Retry decryption fetches
only those events, retries key recovery and indexes successes. Pauses, quota
refusals and fetch/decryption failures retain unresolved references. The list
is bounded; reaching its limit pauses before skipping a page. Old downloads
stored only a count and need a fresh scan to collect event references.

The index remains device-local. Reconnect indexes received timeline events, but
does not automatically backfill a gap omitted from a limited Matrix sync. A long
offline period can leave missing search context until history is fetched. The
history-download tool can fill it within the selected scope and cache limit;
automatic checkpoint-based gap recovery is not implemented yet.

### Proposed automatic gap recovery

Keep a per-room contiguous coverage boundary, identified by event ID rather
than device time. When a limited sync omits history, save its pagination token
and the previous boundary as a pending gap before advancing coverage. Fetch
backward in small, rate-limited event-only batches until that boundary is found.
Save each cursor only after index admission and failed-event bookkeeping succeed.

Use a separate checkpoint from manual history downloads. Run one foreground job
at a time, yielding to manual downloads and retries. Respect the chosen chat
scope and pause at the cache limit without pruning context to make room for a
backfill. Leave unresolved gaps visible if access, keys or history visibility
prevent recovery. A newly joined room without a boundary should not trigger an
automatic download of its entire history.

Further performance, GPU and comprehensive cache/traffic profiling is deferred
by request. No sustained-frame-rate or total-cache-size fix is claimed.

See [storage details](storage-and-bandwidth-investigation.md) and
[server setup/rollback](../server/README.md#account-storage-and-profile-metadata).
