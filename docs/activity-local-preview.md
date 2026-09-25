# Activity / media local preview — 2026-09-25

Local Linux review build on top of 0.9.34+107. This is not a published release
and does not change the public version number. No server changes are required.

## Included

- Compact DM/chat list without message previews. Online recipients show their
  status or active game/music, with matching controller/music icons.
- Member-list statuses and quiet inline Admin/Mod badges on desktop and mobile.
- Smaller desktop DM avatars, compact member rows, muted normal navigation names
  that brighten on hover/selection, and a small first-message header/content gap.
  Unread entries retain their deliberate bold emphasis.
- The right-side profile card has an X that returns to the member list, including
  while its profile is still loading.
- Bold unread channels, including messages without a notification count.
- Animated selected/unread markers on desktop and mobile, respecting reduced motion.
- Restored seed-generated accent palettes; explicit JSON theme tokens still win.
  Icons follow the palette on Windows too; timeline hover remains neutral.
- Desktop notifications play SeND's sound rather than relying on inconsistent
  notification-daemon support. Separate notification and call-cue volume controls.
- Public, expiring `net.deltiecord.activity` profile extension, shown in profiles,
  DM timeline headers and online list subtitles. Old clients ignore the extension.
- Native Linux desktop-entry/Steam-manifest discovery and Windows visible-process
  discovery. Local executable icons are reused when available. Unknown programs
  require classification. Steam manifests alone do **not** prove an app is a game.
- Device-local allow/block, rename and Game/Music/Application rules, plus manual
  executable selection. Detection and sharing are independent, default-off switches.
- Optional Linux music detection through `playerctl`, including MPRIS album art
  (local WebP/JPEG/PNG and bounded public HTTPS images). Covers are normalized to
  384px PNG, stripped of source metadata and cached; only normalized MXC artwork is
  shared. Profile blocks have separate “Currently playing/listening to” headings.
- MPRIS position/duration and paused state feed an optional song progress bar with
  `hh:mm:ss` elapsed/total clocks. Five-second local scans reconcile seeks and
  pauses; only the small progress widget ticks each second. Normal progress is
  interpolated between profile updates, not broadcast every second. Unsupported
  players and Last.fm-only feeds have no invented progress.
- Dedicated Account → Activity page. Last.fm browser authorization replaces the
  end-user API-key form. SeND's own application credentials are required
  before this can be used; local previews load Cleo's 0600 credential files
  securely at build time. Existing local feed settings survive.
  A missing `playerctl` simply disables local music discovery.
- Experimental Linux Discord IPC presentation bridge: SET_ACTIVITY text and local
  executable identity only, bounded payloads/clients, private socket permissions,
  no takeover of occupied sockets, no Discord credentials, join secrets or commands.
  Owned stale sockets are recovered only after an explicit connection refusal and
  unchanged owner/inode checks; live listeners, symlinks and normal files remain.
- Steam shortcut IDs are joined to actual install paths and categorized launchers.
  Running Steam alone no longer impersonates the first installed game. Local
  categorized CS:S/Stardew shortcuts supply classification and icons, but installed
  entries must still match a running executable before they can be shared.
- Worker jobs now transfer only scan data, not source objects that can hold live
  IPC sockets. Regression tests cover repeated scans with an active socket,
  autonomous recovery/renewal and retry-after backoff, including failed clearing.
  Error messages distinguish detection, artwork upload and publication. Missing
  activity fields (404) are normal absence, not a reason to stall other users.
- Desktop-local FFmpeg optimization before Matrix upload/encryption: H.264/AAC,
  longest dimension up to 1920 / short side up to 1080, 30fps, up to 4Mbps video,
  adaptive 20MiB target with a 24MiB checked maximum. No stretching or truncation.
  Encoded dimensions/duration and a new thumbnail accompany the new bytes.
  Captions, spoilers, reply/thread links and SDK-generated encrypted attachment
  hashes remain on the existing send path. Progress/cancel and original-quality
  fallback are available. No external conversion service is used.

## Privacy and lifecycle

Process paths, installed-program lists and per-program rules stay on the device.
There is no usage telemetry, catalogue submission or opt-out collection.
Settings and optional Last.fm key are account-scoped in local secure storage;
they are not Matrix account data. Last.fm requests contact Last.fm directly.

Only an explicitly enabled activity's display name, details, type, start/expiry
and uploaded icon are published. This is public profile information, not E2EE.
Invisible mode / disabling presence suppresses publication. Entries expire after
two minutes, are renewed roughly once a minute and cleared on disabling/logging
out when the server is reachable. Expiry prevents stale display, not retention by
other clients or the server. Active publisher coordination across multiple
desktop devices is not implemented yet: enable sharing on one desktop at a time.

## Preview limitations / remaining work

- **Steam library linking is not implemented.** Verified identity and public-library
  access need a deliberate OpenID/API credential arrangement; no fake verified link.
- **Windows Discord named-pipe adapter is not implemented.** Windows local process
  detection is present but requires Windows testing. Linux games using alternative
  sandbox/Flatpak IPC paths, Proton and RPC artwork need further compatibility tests.
- **Android-native video encoding is not implemented in this local preview.** Android
  currently sends originals. PWA/iOS originals are the explicitly agreed exception.
- FFmpeg and ffprobe must currently be installed on the desktop PATH. They are not
  bundled by this preview. Packaging/codec availability must be resolved before
  releasing desktop builds. Unsupported inputs fail visibly rather than silently
  uploading an original or a truncated conversion; choose original quality to retry.
- General detection is intentionally conservative, not a complete Discord-scale
  game database. No upstream catalogue is downloaded or community data collected.
- Last.fm application credentials were verified live; end-user browser consent
  and iOS standalone-PWA return flow still need hands-on review. The user reports
  an hour of correct live music/game switching in preview four.
- External profile-field support is required for sharing; failures appear in Activity.
- Activity reads wait 15 seconds after startup, run one at a time at no more than
  one per second (eight per pass), and pause for a minute after a read error.
  They must not compete in a startup burst with the main Matrix profile refresh.
- Notification-daemon policy, real speakers, and cross-device activity display need
  hands-on review. Automated checks cannot prove that an OS actually plays audio.

## Review checklist

1. Restart the local preview. Check compact lists, online status, Admin/Mod badges,
   unread channels, rail animation and generated accents in stock/JSON themes.
2. Account → Activity: detection starts off. Enable detection only and
   verify local candidates; classify one or add its executable. Block it and confirm
   it is excluded. Enable sharing only when ready to publish public activity.
3. View the publishing account from another preview client; check profile/DM/list
   activity. Disable sharing and check it clears. After an unclean shutdown it must
   disappear after its two-minute lease expires.
4. Close Discord before enabling compatibility mode. Check a game with Discord RPC.
   If Discord owns the socket, verify SeND warns instead of replacing it.
   Starting Steam alone must not publish Stardew. Start/stop the actual games and
   allow up to one five-second scan. Old manual Steam rules are ignored for safety.
   Play music in Psysonic: its cover should appear alongside the track/artist.
   Pause, resume and seek; check progress catches up within one scan and does not
   continue when paused. Wait over two minutes without changing any settings to
   check that activity keeps renewing and does not expire spuriously.
5. Try notification/call test buttons at 0%, 25% and 100%. Receive a message in
   another room and check cadence; open that room to reset it. No audio is added to
   Android foreground notifications by this patch.
6. Send a short landscape and portrait video. Check progress, cancel, thumbnail,
   rotation/aspect, duration, spoiler/caption and decrypt/play in a second client.
   Audio & video → disable optimization to send an original or a long clip.

The previous installed CI bundle is retained for rollback. No account data or
database migration is performed by installation itself.

## Validation

- Full Flutter suite: 402 passed, two environment-dependent skips. The updated scroll regression
  now anchors to a visible timeline message instead of the deleted DM preview.
- Activity regressions pass, including startup deferral / read-error backoff,
  opt-out during upload, inactive-program exclusion and activity-card labels.
  Native tests cover launcher matching, stale/live IPC sockets, bounded artwork
  and Last.fm request signing. The separately enabled host smoke check passed for
  Psysonic's actual cached WebP cover and CS:S/Stardew classification and icons.
- Fourth-preview regressions cover live-IPC worker scans, automatic recovery and
  renewal without settings changes, clear-error retry backoff, Last.fm's public
  display gate, playback parsing/serialization/clocks, and the profile close button.
- Last.fm application authentication was checked live with the provided files;
  neither credentials nor auth tokens were printed. Repository credential scan: clean.
  Focused audio and real FFmpeg conversion/cancellation
  checks also pass (FFmpeg integration runs only where FFmpeg/ffprobe are available).
- `flutter analyze --no-pub`: clean. `git diff --check`: clean.
- Local release builds and the existing E2EE linkage check succeed. No CI jobs,
  remote pushes, releases, server deployments or live-account test posts were made.
- The initial native smoke launch restored the existing session but logged two
  Matrix rate-limit exceptions during startup. Activity reading was subsequently
  staggered/backed off; the precise origin of those exceptions still needs tracing
  if they recur. A successful build is not a claim of complete live interoperability.

## Last.fm application setup

The browser-link flow follows Last.fm's desktop token authorization protocol:
request token → browser approval → finish linking. It obtains the confirmed
username and discards the write-capable session key because presence only reads
the public now-playing feed. It never scrobbles or edits a library.

`packaging/build-local-activity-preview.py` validates the owned regular 0600
`/home/cleo/lastfm-api.key` and `lastfm-shared.key` files, checks application auth
without displaying its token, and builds with a temporary private dart-define
file. It deletes that file on completion. Do not commit credentials. These are application
credentials, not end-user passwords; a desktop binary's embedded application
secret is extractable. A server-side signing broker is a possible future option.
Local music detection/artwork needs no Last.fm key. Last.fm browser approval must
still be performed by the user; the automated check does not authorize an account.

The owner confirmed written Last.fm approval on 2026-09-25. Public display is
enabled in the current source (`LASTFM_PUBLIC_DISPLAY_APPROVED` defaults to true);
the explicit false build override remains available if approval is revoked.
Users still must opt into sharing. The installed fifth preview predates this
change and remains local-only for Last.fm until rebuilt.
Attribution links to the relevant catalogue/user page. Last.fm artwork is not
fetched or republished; the API terms exclude it. Local MPRIS artwork is separate.
Feed requests respect cache freshness and rate-limit backoff. No scrobbling or
library writes, streaming, permanent listening history or telemetry is added.
This is an implementation checklist, not a claim of legal clearance.

Sources: [Last.fm desktop authorization](https://www.last.fm/api/desktopauth),
[Psysonic token authorization](https://github.com/Psysonic/psysonic/blob/main/src/music-network/wires/audioscrobbler/auth/tokenPoll.ts).
[Last.fm API terms](https://www.last.fm/api/tos) govern the approval and data-use gate.

## Fifth preview follow-up

- Last.fm linking/settings and foreground polling are no longer tied to desktop
  process detection. Android, iOS/PWA, and desktop share the same bounded reader.
  No server poller or background detection was added. Native program detection
  remains desktop-only. Local connection settings remain per device/account.
- Browser sign-in prepares its token first, then opens Last.fm on a direct tap,
  avoiding Safari's asynchronous-popup restriction. Finish linking after returning.
  Application credentials must be provided to each platform build; they are
  extractable app credentials, never a user password. No session write key is kept.
- Presence gates activity reads and display. Offline/unknown users are not queried;
  offline transitions discard cached activity and late in-flight responses.
  Away remains visible. Invisible users cannot publish. This is not server-side
  access control over Matrix profile fields; other clients may retain prior data.
- At the time of the fifth preview, Last.fm public sharing remained off pending
  written approval. Approval has since been confirmed; see the follow-up below.
  Local player sharing is unaffected. No Last.fm artwork is fetched or redistributed.
- Music covers have a larger square presentation, with aspect-preserving cover
  cropping rather than stretching or transparent letterboxing. Games retain their
  smaller icon frame. Only the longest artwork dimension is normalized to 384px.
- Desktop activity input tracking now wraps all Navigator routes, including profile
  popups and dialogs. Active presence renews alongside the desktop activity lease;
  manual Away/Invisible settings are respected and presence errors are contained.
- Album cells render previews directly edge-to-edge on desktop/mobile instead of
  scaling a padded standalone attachment. Spoiler reveal state and original-media
  gallery opening are preserved. Duplicate “local time” text is removed.
- New regression checks cover non-desktop Last.fm, foreground/offline transitions,
  late responses, modal input tracking, square cover rendering and filled album cells.
- Fifth-preview validation: 402 tests passed, two environment-dependent skips;
  static analysis and diff whitespace checks are clean. Credential-enabled Linux
  and web release compilations succeeded, and Linux E2EE linkage passed. Web still
  reports the CupertinoIcons font-family warning; no new Cupertino icons were added.
  Physical Android/iOS browser consent and foreground/resume behaviour remain
  hands-on checks. The local web output was not deployed or published.

Local build command: `python3 packaging/build-local-activity-preview.py`.
For a credential-enabled local web compile, append `--target web`; this does not
deploy the result or perform the release web-crypto packaging steps.

Final local bundle: `/home/cleo/.local/share/deltiecord-preview/activity-20260925-5`.
The standard `/home/cleo/.local/bin/deltiecord` launcher and desktop shortcut now
target this bundle. Restart the app to load the activity fixes and styling pass.
Rollback bundle: `/home/cleo/.local/share/deltiecord-preview/0.9.34-107-ci`.

## Approved Last.fm sharing and mobile-layout review

- Written approval confirmed by the owner; public Last.fm now-playing sharing is
  enabled in source and in the local build helper. Existing user consent and
  online/foreground gates remain. No artwork permission is inferred.
- Account → Activity has an independent, default-off switch for a compact
  bottom-of-profile “Last.fm · Last listened to” footer with song, artist and album.
  It shows the most recent completed scrobble, not a false currently-playing state.
  Tapping it opens the validated Last.fm catalogue/user URL.
- The optional `lastfm_recent` object shares the version-1 activity profile record
  and two-minute lease. It can coexist with live game/music activity or stand alone;
  older clients ignore it. No separate poller, background service, persistent
  history or extra profile-read endpoint is added. Only two recent feed entries
  are requested to distinguish a live track from the last completed one.
- Offline profiles hide the footer and are not queried. As with live activity,
  this is client behaviour, not server-side access control over public profile data.
- A separate Chromium window provides a 390×844 touch/mobile viewport at
  `http://127.0.0.1:8765`, using existing fifth-preview web output. It is not Safari
  emulation and does not yet include these unbuilt source changes. The loopback
  preview server does not log requests; no user login/session content is collected.
- No new build, push, release or deployment was performed for this follow-up.
- Validation: 409 tests passed, two environment-dependent skips; static analysis
  and diff whitespace checks are clean. New checks cover completed-track parsing,
  metadata/URL/expiry validation, settings migration, game coexistence, recent-only
  records, opt-out/offline hiding and narrow-layout rendering.
