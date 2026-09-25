# SeND 0.9.35+110 — release notes

Released on 2026-09-26 as latest on GitHub and deltie.net/SeND.
Release commit: `d3d231f45fbc6c29bdbd0a5ca36523007d44a754`;
tag: `v0.9.35-b110`. Android, both Linux package jobs, Windows and PWA CI,
plus the publication workflow, all completed successfully. All ten artifacts
passed SHA-256 verification before deployment. `chat.deltie.net/version.json`
reports build 110, and the local Arch package is `deltiecord 0.9.35-110`.
The existing media service is active with its two Telegram bounds set to 150;
its KLIPY endpoint returned HTTP 200 after the scoped update.

## Last.fm history and artwork

Live activity keeps its short lease and online-only visibility. Completed-track
history now uses a separate public profile field per device:
`net.deltiecord.lastfm_recent.device.<SHA256(device ID)>`.
Its declarative record is `{version: 1, track: {...}}`. Closing/backgrounding the
app does not delete it, and viewers fetch it even when the user is offline.
The newest completed track wins across devices. An explicit opt-out deletes this
device's field; other linked devices remain independent, as the settings explain.
Publication failures back off without preventing live activity or profile reads.

The real Last.fm artwork hostname `lastfm-img.freetls.fastly.net` was missing from
the strict allowlist. It is now accepted alongside the previously supported CDNs,
with the existing HTTPS/path checks. Both live and completed-track parsers select
the largest supplied valid image, without inventing an upscaled URL. Completed
tracks get square artwork in the full-width footer. Missing artwork has a fallback.
No credentials or third-party proxy are involved in image rendering.

Older clients ignore the new history field. They can still see the compatibility
footer while a live activity record exists, but need build 110 for offline history.

## Packs and favourites

- Editors offer **Merge pack** and **Split selected**. Merge retains the source
  pack and resolves alias collisions case-insensitively with numbered suffixes.
  Remove redundant originals separately after checking the saved result.
- Split creates the destination personal pack first, then updates the source.
  On second-save failure the new pack remains safe, the server's original stays
  untouched, and **Save changes** retries the source update without recreating the
  destination. This is deliberately not presented as a cross-event transaction.
- Reorganisation reuses verified accessible MXC references and original media
  type/dimensions, preserving animation without downloading or re-encoding it.
- Maximum pack size is 150. Upload byte limits, conversion resource bounds, and
  service rate limits are unchanged. Deltie's existing Telegram proxy was updated
  using `server/install-media-limit-110.sh`, preserving a rollback copy and all
  unrelated service code. Self-hosters must update the proxy before 121–150-item
  Telegram imports work end-to-end; no nginx or certificate changes are needed.
- Sticker tiles and fullscreen GIF media use long tap/click-and-hold to toggle
  favourites. Plain taps, swipes, and zoom gestures do not favourite media. Sticker
  star indicators are noninteractive. GIFs also expose a screen-reader action.

## Profiles and updates

The DM timeline header replaces presence wording with an activity icon and bare
game/program name while active, instead of a separate activity banner. Profile
cards and DM/member lists retain their existing presentation. Offline and idle
headers fall back to their normal presence labels. Mobile fullscreen images
support double-tap focal zoom/reset while retaining pinch/pan and gallery swipes.

Desktop popovers, full profiles and sidebar cards now scroll inside their fixed
gradient/rounded outline. No internal scrollbar is shown. Mobile keeps the same
fixed-frame behaviour introduced in 109.

Update checks run at startup and on foreground resume (five-minute cooldown),
and periodically for a long-lived foreground session. One prompt per new build
is shown in-process; checks continue after a successful no-update result. Prompts
wait behind other dialogs. The PWA compares compiled build constants and offers
**Reload app**, warning about unsent drafts/uploads. No forced reload is performed.

## Verification and remaining manual checks

Local validation: Flutter analyzer clean; final full suite **451 passed, 3 skipped**;
final editor/gesture follow-up **13 passed**; Chromium browser animation,
favourite gestures and update-gate tests **5 passed**; Telegram proxy tests
**13 passed**. Formatting and `git diff --check` pass.
Additional timeline-header, double-tap and favourite-interaction tests: **6 passed**.

Automated coverage includes offline/history publication and opt-out, actual CDN
artwork parsing, independent history-error backoff, multi-device activity,
merge aliases, split failure/retry, 150/151-item boundaries, long-press vs tap/drag,
fixed profile frames, and startup/resume update checks.

Remaining physical-iPhone smoke test: hold a fullscreen animated
GIF, zoom/swipe without favouriting, view the full-width footer artwork while its
owner is offline, and verify **Reload app** moves an installed PWA to a newer
deployed build. Browser automation does not replace this iOS check.
