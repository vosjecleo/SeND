# 0.9.42+133 preview

Local pre-production build, not published. The Arch package and signed arm64
Android preview are installed over the existing apps. Accounts and data were
retained. Android's ABI-specific installer code is 2133.

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
- Attachment image crop/move/quality controls on desktop and mobile. Animated
  images keep their animation; static quality presets are optional. Video presets
  use 12 MiB or 24 MiB limits, or original quality. Browser videos stay unchanged.
- Separate Local storage and Server storage pages. The server page has uploaded
  media categories, remaining allowance and confirmed age/type/source pruning.
- Opt-in encrypted-upload labels and a per-account device-local retry queue.
  Only type/source/reference metadata is shared, not text, filenames or keys.
- The Synapse adapter, PostgreSQL admission guard, guided setup integration and
  existing-stack installer/rollback path. The default original-upload allowance
  is 12 GiB; operators can override it per account.

## Validation

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

Production Synapse, the public PWA, CI publication and the download mirror are
unchanged. Server storage is not enabled on live Deltie yet; that page reports
unavailable until deployment. The API tests used synthetic accounts and isolated
containers, not the production database. The staged installer requires privileged
operator checks before applying it during the deployment window.

## Preview checks

1. Confirm About shows 0.9.42+133. Test clipboard actions with a finger, notification
   shade return, language switching and background/resume with the keyboard open.
2. Check ordinary outgoing replies versus replies addressed to you, short-message
   avatar alignment and unchanged media layout.
3. Edit a pending PNG/JPEG and an animated image. Check crop preview, cancel,
   quality preview, captions and spoilers. Test both video presets and original
   quality with the earlier problematic clips.
4. Test local search scopes, pause/resume and the larger-limit prompt. Downloads
   remain a user action; they do not fetch media files or mark rooms read.
5. Test real closed-app notifications with Sunup. A receiver diagnostic alone is
   not proof of background decryption or notification display. Android Force stop
   is different from swiping the app away.

Further performance, GPU and comprehensive cache/traffic profiling is deferred
by request. No sustained-frame-rate or total-cache-size fix is claimed.

See [storage details](storage-and-bandwidth-investigation.md) and
[server setup/rollback](../server/README.md#account-storage-and-profile-metadata).
