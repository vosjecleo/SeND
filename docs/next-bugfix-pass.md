# Next bugfix pass

Collected 2026-10-10. No version assigned. Implement and push without starting
CI builds or deploying. Device reports remain separate from automated checks.

## Implemented, awaiting user testing

These are code changes, not confirmations from the reporting devices.

- B12: New room/server invitations use notifications as well as the inbox.
  Invite notifications open the inbox without inventing a timeline event ID.
- B13: Linux Minecraft detection recognizes vanilla/Fabric client main classes
  and reads icons from installed asset indexes. Other launchers need checking.
- B14: Opening a forum clears its unread marker and sends a read receipt,
  respecting the public-receipt setting.
- B15: Fully disconnected voice shows no connectivity indicator.
- B16: Space child metadata carries channel type for unjoined rooms. Admins
  backfill known types during discovery; old spaces need an admin refresh.
- B17: Consecutive undecryptable history at the start becomes one notice.
  Events are retained and reappear when keys arrive.
- B18: Successful recovery retries keys/decryption for the open timeline.
- B19: Server settings expose access/discovery. Creating a space asks for the
  encryption default for new channels; mobile room creation also exposes it.
  Existing encrypted rooms cannot be made unencrypted.
- B21: Forum tag suggestions appear only when searching with `#`.
- B22: Search retains its history cursor, continues through empty result pages,
  and loads more on scroll. Stop cancels further paging, not an in-flight request.
- B24: Desktop typing remains available while the previous message sends.
- B25: Missing banner bytes are fetched during profile metadata refresh.
- B26: Steam's Wallpaper Engine entry defaults to application, not game.
- B27: Linux icon lookup includes installed themes, pixmaps and SVGs. SVG
  conversion uses `rsvg-convert` when available. Missing art keeps the fallback;
  this is not a complete icon database or a new Windows icon extractor.
- B28: A backslash inside a formatting pair cancels that pair wherever placed.
- B29: Empty visible timelines fetch older history instead of stopping at
  hidden state events or edits.
- B30: Direct FxTwitter previews reject author-avatar images on text-only posts,
  including when merging with a homeserver card. Homeserver-only MXC images
  cannot always be identified as avatars without origin metadata.
- B32: Desktop height measurement includes trailing spaces/newlines and uses
  the composer's inline styles.

## Partial fixes and device checks still needed

- B01: Circular avatar clips have isolated repaint/save layers. Software pixel
  and frame-lifetime tests pass, but they do not reproduce a native GPU fault.
  Long-session flicker and the GPU cost of the extra layer need checking.
- B02/B31: Language-picker lifecycle transitions retain focus. On Android 11+,
  resume checks native IME visibility before clearing stale Flutter insets,
  including nested timeline layouts. Tests cover a visible keyboard and a hidden
  keyboard with stale insets. Older Android and PWA behaviour need device tests.
- B03: Reproduced a five-second player timeout while the encrypted proxy waited
  for a complete download. Downloads now finish verification before the player
  opens. Both supplied clips play through the corrected path, including a
  throttled download. Mobile displays the uploaded poster and downloads the
  video on Play. Browser uploads now publish dimensions, duration and a poster;
  posters use a later frame to avoid black openings. Old message metadata is
  unchanged. Retest the installed app with both samples before closing B03.
- B10: High desktop GPU usage remains open. No claim of a GPU performance fix.
- B11: Missing RTC peers trigger periodic membership rescans; failed peer
  connections get ICE restarts. Multi-user join/leave churn needs a real call.
- B20: Screen capture requests 1080p/30 and screen senders request up to 6 Mbps.
  Negotiation, network conditions and platform capture limits still apply.
- B23: Sunup uses Mozilla Autopush, not ntfy. Its Matrix adapter is prepared in
  Deltie's existing loopback Web Push worker. Deploy the worker before testing
  the new client route. No server deployment was performed in this pass.

## Requests

- [x] R01 Invite identifiers default to the account homeserver.
- [x] R02 Role mentions notify assigned members who belong to the room.
- [x] R03 Matrix mentions display short names and a light-blue highlight.
- [x] R04 Mark as read is first in room/server context menus.
- [x] R05 Keep the built-in Android service as the simple option; clarify the
  ntfy/Sunup alternative and its privacy implications. OS permission and battery
  restrictions cannot be removed by the app.
- [x] R06 Hide offline users' profile thought bubbles.
- [x] R07 Show elapsed activity time beside the activity heading when available.
- [x] R08 Inline previews retain muted delimiters; escapes cancel preview.
  Draft contents and selection offsets remain unchanged.
- [x] R09 Remove the bundled Aero preset; existing selections use built-in
  appearance. The old JSON remains a theme-engine test fixture.
- [x] R10 Set profile timezone to the current device timezone with one button.
- [x] R11 Enlarge the mobile Send touch target without moving visible icons.

Space creation must offer an encryption default for new channels. Do not imply
that a Matrix Space encrypts children or that existing encryption can be disabled.

## Closed, deferred and evidence needed

- B04 Android video sending: confirmed fixed; compression speed remains a concern.
- B05 Windows white composer: confirmed fixed.
- B06 PWA notification delivery: confirmed fixed; occasional background
  decryption failures deferred by request.
- B07 Mobile screen-sharing crash: confirmed fixed.
- B08 General progressive loading: confirmed fixed; B03/B25 track specifics.
- B09 Rare scroll/input latency: more reproduction evidence needed.

## Validation

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 623 passed, 4 skipped.
- Chrome video-upload test: passed with real metadata and poster extraction.
- Android `:app:compileDebugKotlin`: passed.
- Web Push gateway unit tests: 20 passed in the preceding implementation pass.
- `git diff --check`: clean.

Automated checks cover formatting/escapes, role recipients, notification targets,
search pagination, keyboard lifecycle, icon lookup, missing-history grouping,
FxTwitter avatar suppression and Sunup forwarding. Native RTC, GPU rendering,
Sunup delivery and affected media files still need device testing.

No version/build bump, CI build, release or deployment is part of this push.
