# Changelog

Current latest: **0.9.34+106**. This is the feature-scope milestone; subsequent
work focuses on [hardening and bug fixes toward 1.0](docs/RELEASE_READINESS.md).
Historical entries preserve the scope and terminology of their own releases.

## Deltiecord 0.9.34 build 107 — 2026-09-25

- Expose channel access, history visibility, directory listing and Space defaults;
  discover accessible unjoined channels and join them when opened.
- Add shared Space timeline-event defaults and room overrides, retaining
  protected security/moderation events. These display policies apply in Deltiecord.
- Improve permission editor readability, live role refresh, stale-draft detection,
  member role assignment and banned-member management. Report inaccessible child
  rooms individually during administration operations.
- Resolve role colours from room membership, including reply authors and profiles.
- Restore author headers on media albums and add mobile fullscreen media paging.
- Merge read-receipt streams without losing newer positions; retry read markers
  after sync and foreground updates while preserving visibility/privacy guards.
- Thin profile-avatar borders, align presence indicators diagonally and curve
  thought-bubble trails toward the avatar. Respect mobile forum safe areas.
- Use exact chosen accents for controls and neutral message hover backgrounds,
  including high-contrast themes.
- Check the Latest release channel at startup and retry failed discovery.

Validation and remaining device checks: `docs/build-107-plan.md`.

## Deltiecord 0.9.34 build 106 — 2026-09-24

- Keep onboarding text scrollable with navigation outside the content viewport.
- Share the profile layout across desktop/mobile cards and editors, use a
  consistent banner ratio, and position crop drafts behind the real card masks.
- Use connected thought-bubble outlines and limit pronouns to 16 graphemes.
- Start a fresh rich-text document after sending to discard pasted styles.
- Merge PWA safe-area insets without double padding; scale all layout insets
  with the interface rather than shifting every device by a fixed amount.
- Add personal account-synced room event filters, with global defaults and
  room overrides. Encryption notices and moderation actions remain visible.
- Administration: named multi-role assignments, ordered name
  colours, server-profile badges, and explicit room permission propagation with
  manual-power preservation and partial-failure reporting.
- Split Administration into Roles and Rules. Roles have stable IDs, names,
  colours and numeric power levels; highest assigned power wins, while the first
  ordered coloured role supplies the displayed colour. Saving definitions does
  not silently rewrite child-room permissions.
- Expose applicable Matrix thresholds for membership/moderation, message/state
  events, encryption, room access/history/metadata, channel/category ordering,
  server packs, role definitions, pages, voice membership and notifications.
  Preserve manual powers and contributions from multiple Spaces during explicit
  propagation; report authority violations and partial failures.
- Add standard Matrix discussions in a desktop side pane or mobile page, with
  paginated replies, shared media rendering, attachments, edits, reactions,
  thread-specific receipts and notification navigation. Collapse replies in the
  main timeline without changing its pagination/scroll machinery.
- Add forum room presentation, readable Matrix post bodies plus declarative
  title/tag metadata, image covers, search/filtering, recent-activity sorting,
  unread indicators and an account-synced Following list. Failed posts retain
  their drafts for retry. Following organises posts; room rules control alerts.
- Discover active older forum roots through the server thread index, with an
  ordinary-history fallback for unsupported homeservers. Titles allow 120
  graphemes; posts support up to five tags and optional image covers.
- Discover homeserver browser-login methods and support Matrix SSO / SDK OIDC
  with PKCE, state-bound callbacks, cancellation and SDK token persistence.
  Device encryption verification/recovery remains a separate step.
- Use external browsers with random loopback callbacks on native platforms and
  same-origin validated callbacks on web. The Android return link carries no
  login credentials. Prepare a narrow nginx callback rule that disables access
  logging/caching; operator application remains required on Deltie.
- Keep data in existing Matrix events/state/account data; no new SQL migration.
  Preserve standard message/media fallbacks for clients without forum/role UI.
- Validation: 366 tests passed with one existing skip; static analysis clean.
  All four platform CI builds passed, including Linux package smoke tests and
  the web autofill regression. Stabilize the browser test's semantic-layout
  timing and retain diagnostic screenshots on failure.

Published as Latest on GitHub and deltie.net; PWA deployment verified at build
106. Stable was not promoted. Documentation was subsequently reconciled with
this milestone, with current guides separated from historical investigations.

Hardware/cross-client authentication validation remains outstanding. Hosted
browser SSO requires the narrowly scoped auth callback hosting rule.
See `docs/build-106-plan.md` for details and implementation boundaries.

## Deltiecord 0.9.33 build 105 — 2026-09-24

- Fix web attachment selection by reading browser File objects directly while
  preserving Safari's user activation for camera/photo/file pickers. Avoid
  CSP-blocked blob fetches and bound mobile selections to 20 files / 64 MiB.
- Use same-origin Telegram import requests on web and leave the browser's
  User-Agent alone. Close the expression picker before pack management/import,
  surface import failures and refresh the catalogue afterwards.
- Resolve shared sticker/emoji packs across joined servers, not just the
  currently selected room. Non-admin members can subscribe; subscribed packs
  refresh when their server state changes. Report subscription failures.
- Add a web-only preview bridge for supported public providers, with validated
  DNS-pinned HTTPS connections, redirect/type/size/range checks and request
  limits. Keep native preview networking unchanged and existing opt-in policy.
- Repair stale iOS viewport pan after keyboard dismissal without interfering
  with active typing or pinch zoom. Safari's native accessory bar remains;
  real-device hit-testing confirmation is still needed.
- Refresh the timeline when foreground focus actually returns, including quick
  resume/focus races. Sort confirmed messages by server timestamp with stable
  event-ID ties, keeping pending local echoes provisional.
- Keep rich spoiler-text receipts on the content row and expose uncategorised
  channel reorder controls in server settings.

- Review iteration 5: full-width centred date separators; compact two-line
  profile speech bubbles alongside avatars, pronouns beside Matrix IDs, plain
  biographies and local time underneath. Apply themes without transitions on
  desktop too, avoid stale preferences in settings callbacks, and report
  theme-application failures rather than silently ignoring them.

- Review iteration 4: match the profile-column underlayer to the bottom panels;
  opaque, aspect-correct spoilers with session-only reveal state; visible desktop
  call disconnect and day separators. Crowded receipts move to sender headers
  without squeezing media. Anchor messages independently of date labels, and
  apply mobile theme changes immediately rather than through a theme animation.
  The intermittent mobile appearance issue still needs on-device confirmation.

- Review iteration 3: selected/unread rail indicators, tighter Aero corners,
  glass rounded-square avatars, clearer translucent expression/pack popups,
  and public-domain Tango icons. JSON themes may override supported semantic
  icons with bounded embedded PNGs; unknown/invalid entries use stock icons.

- Review iteration 2: move the profile card to the top inset and separate its
  footer into the bottom island row. Expand declarative themes with component
  gradients, border/highlight layers, bounded static texture, shadows, glass
  expression popups, hover transitions and an optional classic icon treatment.
  Restyle Aero light/dark chrome with stronger dimensional contrast. No custom
  executable shader, remote texture loader or idle animation loop is introduced.

- Inset the desktop profile preview as a floating outlined card, aligned with
  the composer bottom margin. Strengthen profile gradients and refine banner,
  avatar, headings, sections and footer spacing. The primary profile colour
  controls both the outline and the top of the gradient.
- Subtly refine selected conversations, panel boundaries and sender spacing
  without changing column widths or message/composer horizontal alignment.
- Add versioned declarative JSON themes, semantic tokens, built-in inheritance,
  safe fallbacks and dynamically generated Appearance controls. Respect the
  existing account-sync/local-only appearance preference.
- Bundle Aero Glass with blue-grey surfaces, restrained gloss, bounded blur,
  borders, light/dark variants and configurable accents. Accessibility settings
  override decorative effects. No scripts or remote theme assets are executed.

## Deltiecord 0.9.32 build 104 — 2026-09-24

- Add composer voice messages: microphone when empty, live waveform and timer,
  pause/resume, stop-to-review, local playback, delete and explicit send. Reuse
  Matrix voice-message attachments and encryption; retain recordings on send
  failure. Limit recording to ten active minutes and reject uploads over 16 MiB.
- Make receipt/edited markers smaller and subdued; keep media-only and sticker
  receipts alongside their media and preserve album receipt frontiers.
- Reconcile the visible room's notification on every foreground/resume, including
  unchanged room selection; serialize native dismissal against publication and
  reject publication in the foreground. Dismissal does not advance read markers.
- Replace the fixed theme-button grid with a compact selector and theme dialog.
  Serialize preference writes, reject known stale settings echoes, and cache
  theme data rather than app widgets so live scale/theme changes reach builders.
- Bound mobile send feedback to the button and theme its ink colours. Remove
  the separate GIF favourites background while retaining its category heading.
- Apply colour-emoji font selection to picker and message emoji spans. Prefer
  familiar Discord-style shortcodes, preserve older search aliases, and add
  `sobbing` for the loudly crying face (`sob`).
- Speech-to-text remains a proposal, not an enabled upload service. Platform
  recording, Linux emoji appearance and notification races need device checks
  across real hardware, particularly Safari/PWA microphone codecs.

## Deltiecord 0.9.31 build 103 — 2026-09-24

- Move sent/read progress markers and edited labels after message content.
  Show receipt frontiers rather than repeating acknowledgement on every message;
  edit acknowledgements use the actual replacement event's receipt state.
- Grow the desktop composer for wrapped drafts, center its text, and keep the
  user/profile islands independently sized. Center desktop timeline avatars on
  the first sender-and-message line. Align mobile channel icons with categories.
- Stop outgoing settings pages overlapping the incoming page; correct the space
  menu return direction and respect reduced motion. Refresh inherited theme
  configuration on resume without resetting the session or room selection.
- Group settings into Account, Preferences and App, with larger entry labels.
  Security includes existing encryption controls and a password-change dialog.
  Theme choices wrap into fewer columns on narrow screens. The mobile colour
  picker is centered and has an explicit Apply/dismiss button.
- Confirm logout, dismiss account overlays and clear in-memory image/draft UI
  state after successful logout. Preserve the current screen when cancelled.
- Preserve existing rich formatting when editing messages, including mobile
  range edits; custom emoji insertion no longer disables typed Markdown.
- Keep Search and Call outside the room menu on desktop and mobile, and move
  secondary actions into the menu with clearer notification controls.
- Count emoji/sticker usage after successful sends, not picker clicks or draft
  deletion. Add a frequently-used sticker section and visible favourite controls.
  Order favourites before frequent items and packs; show GIF favourites in their
  own category before Trending. GIF favourite controls appear only fullscreen.
- Replace placeholder notification/call cues with VosjeCleo's original sounds
  and remove the old sound attribution.
- Protect Android's Matrix database with SQLCipher and a securely stored random
  key, with a verified atomic migration that never resets data on failure.
  Confirm formatted-link destinations before opening them. Verify declared
  ciphertext SHA-256 before decrypting encrypted video, with bounded downloads.
- iOS/PWA-specific camera, picker and lifecycle investigations are deferred to
  the following build. Native SQLCipher migration and physical-device lifecycle
  checks still need device validation. Packages are built by CI; this release is
  published to latest, not stable.

## Deltiecord 0.9.30 build 102 — 2026-09-23

- PWA-only password autofill fix: use persistent, labelled browser-native
  username/password fields with standard autocomplete hints on login/signup.
  Read autofilled values directly on submit, including managers that do not
  dispatch input events. Keep Matrix authentication and native apps unchanged.
- Preserve registration validation and clear password fields on mode changes
  and disposal. Credentials are never submitted as a URL or native HTTP form.
- Add browser regression tests and web-only release automation. Android,
  Linux and Windows remain on build 101; stable is unchanged.

## Deltiecord 0.9.30 build 101 — 2026-09-23

- Keep build 100's complete Flutter application; do not ship the experimental
  HTML adapter or replace the Matrix SDK/cryptography implementation.
- Coalesce web backend notification bursts and yield during room metadata/key
  processing. Stop treating unchanged absent avatars as metadata changes, and
  reuse locally stored last-message session keys before requesting backups.
- Restore backup sessions needed by the loaded timeline instead of importing
  every historical key in the room on entry. Older history retains SDK key requests.
- Add an always-visible desktop room search bar, a smaller Home/Space heading,
  and inbox access beside search. Both layouts show a red pending-invite dot and
  explicit accept/ignore actions; the inbox updates while open.
- Resolve Android invitation pushes from authenticated pending membership,
  without requiring joined-room history access or message unread counters.
  Tapping an invite notification opens the inbox; handling it clears the alert.
- Subscribe room panels directly to backend updates so category visibility and
  voice participant changes no longer require navigating away and back.
- Open the voice-channel overview before joining on mobile, matching desktop.
  Opening a channel alone does not join or start microphone capture.
- Show Recent photos/videos from the accessible device library, ordered by
  modification time, rather than relying on an album. Surface limited access
  with a control for selecting more photos.
- Add focused navigation, invite and notification-batching regression tests.
  Remaining validation: real iOS performance, large-account recovery, and
  physical-device push delivery. These changes are not a claim that every
  browser's performance problems are resolved.

## Deltiecord 0.9.30 build 100 — 2026-09-23

- Reuse the application theme/navigation configuration for ordinary backend
  updates instead of regenerating it for every sync, typing, and receipt event.
  Suppress redundant connection-status notifications; chat updates still flow.
- Wait for initial account settings before completing a fresh login or saving
  preferences, protecting synced appearance from premature default writes.
  Cancel pending preference-save timers when replacing or ending a session.
- Show encryption-recovery stages and add credential-free profiling markers.
  Coalesce concurrent recovery requests; Matrix SDK cryptography is unchanged.
- Stop Space settings pages overlapping during navigation. Reduce Motion
  skips these transitions and disables page transitions on iOS/macOS/Windows
  as well as Android/Linux.
- Remove the obsolete GIPHY footer, retain Search KLIPY attribution, and update
  About credits. Move README web-install instructions below the introduction.
- Exclude the homeserver configuration field from login credential autofill
  and disable credential autocorrection. Password-manager compatibility still
  requires real-browser/manager validation.
- Keep timeline scrolling/media-height changes deferred. These targeted web
  improvements do not establish that all interaction lag or the reported
  two-minute recovery delay is resolved; see the build-100 investigation report.

## Deltiecord 0.9.30 build 99 — 2026-09-23

- Add a shared-code Web/PWA target with mobile and desktop layouts, SDK-owned
  IndexedDB session/crypto persistence, single-tab session ownership, and
  install guidance for iPhone/iPad, Android, and desktop browsers.
- Add Web Push registration, a generic-message service worker, notification
  navigation/clearing, and a bounded gateway authenticated by short-lived Matrix
  OpenID proofs. iOS delivery requires Home Screen installation and real-device
  validation; the gateway never receives Matrix session tokens or message text.
- Replace GIF search/trending with KLIPY through a server-held key. Preserve
  existing favourites, resolve KLIPY GIF links under the chosen preview policy,
  and allow inline/fullscreen favouriting of source-tagged GIFs.
- Share bounded GIF byte caching and lifecycle-aware rendering between search,
  favourites, inline media, and fullscreen viewing.
- Canceling an edit clears its composer text and custom-emoji formatting on
  both desktop and mobile; canceling a reply still preserves the draft.
- Resume synchronization invalidates a suspended long poll through the SDK
  before issuing a fresh sync, retaining the existing timeline and scroll anchor.
- Add a cached Web/PWA CI job and include the web archive in release verification.
- Document the image-heavy scroll investigation without changing scrolling code.

- Prefer original GIF/WebP clipboard data over flattened PNG alternatives on
  desktop and mobile, including desktop rich-editor paste callbacks.
- Use animated source URLs for older favourites saved with still previews.
- Render selected custom emojis inside the desktop composer while preserving
  alias text, stable references, and editing offsets. Plain aliases stay text.
- Left-align stickers with message content on desktop and mobile.

## Deltiecord 0.9.29 build 98 — 2026-09-22

- Give animated images their own bounded, lifecycle-aware frame decoder so GIF
  playback is independent of paused UI tickers. Preserve autoplay/Reduce Motion
  preferences and restart decoding after returning from the background.
- Keep quiet Android notification updates on the same visible notification
  channel instead of moving them into a low-importance silent channel.
- Retain a bounded attachment-event cache across room switches, and reset image
  loading state when a recycled message row receives a different attachment.
- Consolidate desktop room tools into the three-dot menu and keep the emoji
  button immediately beside Send.
- Add a unified Emoji, GIFs, and Stickers picker, with emoji favourites and
  frequently used sections and sticker/emoji pack management under Stickers.
- Lower the mobile keyboard when opening the expression picker, without
  automatically reopening it after selecting an emoji.
- Replace mobile's long attachment menu with a paginated photo/video grid,
  camera tile, and floating Picker/Poll/Files actions. Clipboard image paste
  remains available from the composer's text-selection menu.
- Request an Android IME draft-state reset after sending without hiding and
  showing the keyboard window. Physical keyboard Caps Lock remains OS-managed.

## Deltiecord 0.9.29 build 97 — 2026-09-16

- Reset every Android per-conversation alert cadence when Deltiecord opens, so
  the next message can vibrate immediately after the app is backgrounded.
- Prevented in-flight UnifiedPush workers from restoring a cleared cooldown or
  posting after the app/room was opened, and suppressed already-read events.
- Recreated animated image codecs after Android resume, recognized normalized
  GIF/APNG/WebP MIME metadata and GIF signatures, and made GIF-provider video
  renditions loop continuously while preserving Reduce Motion behavior.

## Deltiecord 0.9.29 build 96 — 2026-09-16

- Added first-party account registration for `matrix.deltie.net`, including
  password-manager autofill, password confirmation, Matrix UI-auth handling,
  friendly username/rate-limit errors, and automatic sign-in after creation.
- Automatically onboard newly registered accounts into the Deltie Space and
  its public Announcements and General channels, with explicit server-side
  registration throttling.
- Re-armed Android’s per-conversation five-minute alert cadence whenever its
  notification is opened, acted upon, or swiped away, without muting or
  disturbing other conversations.
- Prevented stale room membership state from evicting the already cached own
  profile avatar while a timeline hydrates.
- Added safe promotion of personal sticker and custom-emoji packs to a server:
  existing stable MXC media IDs are reused, the server pack is subscribed
  account-wide, and the personal source is removed only after publication.
- Renamed the user-facing Regular appearance option to Gray while preserving
  its stored setting and palette for compatibility.

## Deltiecord 0.9.29 build 95 — 2026-09-16

- Unified own-user, room-list, timeline, and profile avatar caching; validate
  sender avatar metadata on newly sent/received messages and propagate changed
  avatars throughout the app without re-downloading unchanged media.
- Made profiles cache-first with automatic background refresh on open, removed
  the manual refresh control, and increased status refresh frequency.
- Added an encrypted-room warning when the current device/account encryption
  setup is unverified or needs attention, and replaced low-level Base58 errors
  with an actionable invalid-recovery-key message.
- Repaired missing and incorrect GIF/image geometry from encoded dimensions,
  added full-image fallback when a Matrix thumbnail is unavailable, and refresh
  expiring YouTube playback URLs immediately before opening a video.
- Added Android keyboard image insertion, bounded Android Share-sheet import for
  text/images/videos, and an explicit mobile Paste image action.
- Removed clipboard object-replacement markers from attachment captions so
  Windows multi-image pastes no longer emit visible OBJ message rows.
- Fixed message grouping across member/system events after a display-name
  change and made desktop timeline avatars slightly larger and centered.
- Added a device-local appearance mode, four clearly named themes (Light,
  Regular, Dark, Night), a new deeper charcoal Dark palette, and a safe legacy
  theme migration.
- Fixed light-theme composer foregrounds, improved neutral high-contrast
  separators and avatar fallbacks, completed the curved mobile panel edge, and
  made reduced-motion settings navigation snap without constructing a
  transition.
- Prevented a cancelled mobile navigation swipe from becoming a message reply
  gesture.
- Fixed the Windows installer desktop-shortcut target and added a CI installer
  smoke test that verifies the shortcut points to the installed executable.
- Kept the Android first-run tour phone-only, with Close on its final page,
  Matrix homeserver caveats, password-manager-ready login/password fields, and
  detailed ntfy/UnifiedPush setup and public-rate-limit guidance.

## Deltiecord 0.9.28 build 94 — 2026-09-15

- Fixed Android’s five-minute alert cadence so each conversation owns an
  independent alert identity and atomically committed cooldown timestamp.
- Recreated mobile video players after Android suspend/resume, discarded stale
  near-end seek positions, learned natural video dimensions at playback time,
  and retained a generated poster-frame fallback for link-preview videos.
- Added bounded native first-frame extraction for Android camera uploads so
  newly sent videos include accurate rotation-aware dimensions, duration, and
  thumbnails without routing arbitrary conversion work through a public API.
- Made failed inline image loads retryable, preferred bounded Matrix thumbnails
  in the timeline, and retried stale media requests after returning to the app.
- Folded adjacent captionless image/video-only messages into compact media
  albums while excluding GIFs, captions, replies, and messages five minutes
  apart.
- Added editable trusted link-preview domains, including the ability to disable
  a bundled provider without weakening exact hostname-boundary checks.
- Added explicit personal/server destinations for imported sticker and emoji
  packs. Published server packs can be added account-wide and retain their
  stable Matrix room/state reference so owner edits propagate to subscribers.
- Rendered explicitly selected custom emoji in the Android composer, kept
  duplicate typed aliases literal until a specific result is selected, and
  added `:name\:` as a plaintext opt-out syntax.
- Prevented a cancelled room-panel swipe from becoming a message reply swipe,
  and standardised desktop presence badges at the avatar’s bottom-right.
- Added password-manager autofill semantics to login and account-password
  prompts, refreshed the first-login presentation, and documented limitations
  that custom homeservers may impose on optional Deltiecord services.
- Reworked the first-run tour’s Android notification guidance with ntfy setup,
  battery/rate-limit notes, and a dedicated-provider explanation. Desktop no
  longer sees the Android page and the tour now ends with Close.

## Deltiecord 0.9.27 build 93 — 2026-09-04

- Made transparent-canvas trimming the default for imported and reprocessed
  static custom emoji while keeping it optional, with a stable live preview.
- Added editing for manageable personal and server emoji packs: reopen a pack,
  reprocess its artwork, rename aliases, and rename the pack without replacing
  unrelated personal packs.
- Rendered emoji-only messages at 64 logical pixels for both Unicode and custom
  emoji, while returning inline custom emoji to a compact 20-pixel size.
- Raised the stock mobile text scale to 110% without changing the desktop
  default or overwriting deliberate existing accessibility sizes.
- Replaced Android's unreliable save-as image flow with a single Save image
  action that writes through scoped storage to Downloads/Deltiecord.
- Kept cached generated build tooling outside CI formatting checks and made
  verified Flutter archive cache guards portable across Linux containers.

## Deltiecord 0.9.27 build 90 — 2026-09-04

- Fixed custom-emoji imports silently completing without becoming available
  in the emoji picker or `:alias:` autocomplete.
- Stored ordinary personal packs together in Matrix's interoperable personal
  image-pack event, with opaque per-pack identities and collision-safe item
  keys so importing emoji preserves existing sticker and emoji packs.
- Added authoritative post-write verification and SDK-cache reconciliation so
  a paused `/sync` cannot leave a successfully uploaded pack invisible.
- Preserved legacy personal packs during migration and made deletion remove
  only the selected pack from a merged personal collection.

## Deltiecord 0.9.27 build 89 — 2026-09-04

- Fixed personal sticker and custom-emoji imports replacing the previously
  saved pack by assigning additional packs distinct synced account-data slots.
- Kept the first personal pack in Matrix's interoperable image-pack slot,
  added independent removal and safe reuse for up to 64 active personal packs.
- Waited for authoritative Matrix sync after personal-pack writes and refreshed
  packs when synced sources change, so imported emoji appear without reopening
  the picker repeatedly.
- Added visible progress while uploading imported packs and increased inline
  custom-emoji rendering from 20 to 26 logical pixels.

## Deltiecord 0.9.27 build 88 — 2026-09-04

- Added optional transparent-padding trimming when importing static custom
  emoji, fitting visible artwork into a centred 128×128 canvas without
  stretching it; animated emoji retain their original animation and canvas.
- Made inline custom emoji tappable/clickable in message timelines so their
  accessible source pack can be inspected and added on mobile or desktop.
- Preserved a stable source-pack hint in newly sent custom emoji while still
  resolving older emoji by their immutable Matrix media ID and degrading
  gracefully when a pack is unavailable.

## Deltiecord 0.9.27 build 87 — 2026-09-04

- Fixed sticker and custom-emoji previews permanently waiting on a
  self-referential completion future, including inline historical emoji.
- Added bounded in-memory reuse for Matrix sticker media and newly uploaded
  pack assets, while retaining timeouts and graceful name fallbacks.
- Made custom emoji available immediately in the picker, grouped them by pack,
  and added validated per-item aliases for Telegram and local imports.
- Applied the selected Dark, OLED, or Light palette to attachment, sticker,
  emoji, and pack-management surfaces.
- Made Telegram imports more resilient to intermittent upstream stalls with
  bounded retries, earlier upstream timeouts, and cached static and converted
  media that avoids redundant Telegram downloads.

## Deltiecord 0.9.27 build 86 — 2026-09-04

- Added bounded server-side conversion of Telegram TGS and WebM animations to
  animated WebP, with separate 128px emoji and 256px sticker outputs.
- Restricted conversion to Bot API-resolved pack items and added fixed media
  bounds, subprocess resource limits, per-client and global quotas, two
  conversion workers, and a bounded result cache; arbitrary uploads and URLs
  are never accepted.
- Reworked the sticker picker into compact, theme-aware mobile sheets and
  desktop dialogs, including search, favourites, pack actions, removal, and
  Matrix-compatible global room-pack enablement.
- Rendered `m.sticker` events as dedicated 128px stickers, opened their pack
  instead of generic image actions, and included stable pack hints in newly
  sent events without breaking standard Matrix clients.
- Added retryable, four-at-a-time Telegram preview/import downloads and made
  transient failures recover instead of poisoning the download cache.
- Added aspect-preserving 128×128 custom-emoji preparation with transparent
  centring and a previewable bicubic/bilinear choice for oversized assets.
- Fixed Android room/Space navigation after long background suspension,
  notification dismissal races when opening a room, desktop AFK detection
  during keyboard/pointer activity, and desktop bottom-island spacing.

## Deltiecord 0.9.27 build 85 — 2026-09-04

- Fixed Telegram pack links copied from rich message text being rejected when
  they contain invisible direction/format characters, wrappers, harmless
  query strings, trailing slashes, or current `addemoji` link forms.
- Added an explicit release-publisher option for clearing an invalidated
  stable channel while preserving historical artifacts.

## Deltiecord 0.9.27 build 84 — 2026-09-04

- Restyled sticker selection and pack management as bounded desktop dialogs
  while retaining draggable mobile sheets, and made every pack/import action
  reachable through a properly scrollable viewport.
- Nudged the active Android Matrix timeline through its existing SDK
  subscription whenever the app resumes, so messages received during a long
  suspension appear without switching rooms or sending a message.
- Removed repeated room-hero database loads and repeated last-event decryption
  from every sync, prioritised the selected room, and reused already-decoded DM
  avatars directly in the timeline sender cache.
- Added a strict, channel-selectable release command that drives the existing
  platform CI, verifies the exact artifact set, and atomically publishes
  `latest`, `stable`, or both on deltie.net.

## Deltiecord 0.9.27 build 83 — 2026-09-04

- Added custom/server emoji on top of Matrix image packs, including 120-item
  packs, strict 128×128 and 256 KiB per-emoji limits, animated inline
  rendering, stable MXC references, fallback names, autocomplete, picker and
  reaction support, server-scoped permissions, Telegram import, and deletion.
- Preserved custom-emoji references in mobile drafts and kept legacy image
  packs that advertised both `sticker` and `emoticon` usage as stickers.
- Reconciled the mobile navigation subtree and transient gesture/open state
  after Android resumes, so Home and Space selection cannot remain frozen.

- Added selective import of public static Telegram sticker packs through a
  bounded, token-hiding Deltiecord proxy. Animated TGS and WebM stickers are
  identified and skipped until cross-platform rendering is ready.
- Raised personal image packs from 50 to 120 stickers, added aggregate media
  and metadata limits, and preserved each sticker's actual MIME type.
- Made sticker-pack refresh metadata-only and lazily loaded visible previews
  with at most four concurrent requests.
- Made Space categories and channels substantially denser on desktop and
  mobile while retaining full-row interaction and trailing collapse controls.
- Reduced the timeline-to-composer gutter to the typing row's actual height
  and tightened all aligned desktop bottom panels accordingly.

## Deltiecord 0.9.26 build 82 — 2026-09-03

- Fixed mobile attachment-only image and video events rendering an empty text
  row above their media.
- Anchored Home and Space attention badges to their full navigation buttons.
- Made mobile's rail separator follow the rounded room-card corner and removed
  the final physical-pixel seam between the typing backdrop and composer.
- Aligned mobile composer text with timeline content while tightening its side
  margins.
- Removed the desktop resize gutter from layout flow so the timeline and
  composer move left together and the user island no longer crosses into chat.
- Slightly reduced and vertically centred desktop timeline avatars.
- Restyled category labels on desktop and mobile with preserved casing, a
  one-pixel-smaller bold font, leading-panel alignment, and trailing chevrons.

## Deltiecord 0.9.26 build 81 — 2026-09-03

- Added per-installation first-run guidance for preview privacy, Matrix
  recovery, and private Android notification setup with ntfy/UnifiedPush.
- Reworked preview privacy into Never, Known providers, and All public sites;
  homeserver previews remain first, and opted-in provider enrichment adds
  playable YouTube and GIF/media cards where available.
- Fixed Android notification history retaining already-read messages, made
  room notifications clear when their conversation opens, and prevented
  foreground mobile banners from appearing over the active room.
- Added structured Matrix mention/reply highlighting, DM and Space ping
  badges, and a ping-focused inbox model.
- Added local favourites for GIFs, emoji, and stickers, plus bounded creation
  and ZIP import for Matrix-compatible personal sticker packs.
- Fixed poll responses not refreshing their Matrix aggregation after voting.
- Hardened resume handling for stale Android keyboard metrics, interrupted
  gestures, endpoint reconciliation, and account-setting refresh.
- Made the typing backdrop persistent and gradual, while reserving just enough
  timeline space to avoid covering message text.
- Tightened desktop/mobile message and composer alignment, filled mobile Space
  avatars, and added a subtle rail separator.
- Removed obsolete compactness/font controls and the unreliable bundled font;
  merged diagnostics into About and added device-aware session icons.
- Replaced desktop message/call cues with HaelDB's CC0 UI sound #8. Call sound
  remains a separate asset slot for straightforward future replacement.
- Extended reduced motion to snap navigation/settings transitions and disable
  automatic animated-attachment playback.
