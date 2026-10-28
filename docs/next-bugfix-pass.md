# Next bugfix pass

The current intake is the [2026-10-27 follow-up](#intake-2026-10-27) below.
Older sections retain their original release and validation records.

## Intake 2026-10-27

Baseline: published 0.9.41+132. Changes below are local previews, not a new
release. The user approved same-signature Android diagnostic updates in place;
the account, room keys and existing data were retained. Private phone captures
and aggregate diagnostic files remain outside Git.

- **B53 / B22, search storage fails silently. Fixed in the phone preview.**
  Android SQLCipher returns the page-size PRAGMA value as text. A forced integer
  cast aborted index opening after schema setup, and the backend hid the error
  behind a null result. Parse integer/text numeric results for page-size and
  page-count reads. Show a safe failure stage/code without SQL, keys or paths,
  back off automatic failed opens and keep explicit Retry available. The user
  confirmed the index choice now works. A regression test covers text PRAGMAs.
- **B39, dead clipboard buttons. Fixed in the phone preview.**
  Real touch-down/up events reached the toolbar without actions firing. A backend
  refresh during a press reproduced this in a widget test. Flutter's overflow
  toolbar replaces its keyed button subtree when given new button widgets.
  Stable builder callbacks alone were insufficient. Retain button widgets while
  their action/appearance is unchanged, invoking current callbacks. The race
  test now taps real buttons with movement and a sync refresh between down/up.
  The user confirmed Copy/Paste/Select all work with their finger. The repeated
  clipboard/indexing entries in the later report were clarified as old notes.
- **B54, mobile lag and slow Home-menu animations. Preview under device testing.**
  Surface presentation sampled around 50 ms median intervals. Flutter build
  durations were substantially higher than raster durations. Local diagnostic
  counters found roughly 60 keyboard samples and full-shell rebuilds every two
  seconds while idle. Reading geometry asked Android to reapply insets, which
  produced another metrics event and another geometry read. Make reads pure and
  avoid rebuilding on equal geometry. Preserve explicit native resume refreshes.
  Regression tests cover read-only queries, duplicate samples, real geometry
  changes and existing focus/keyboard restoration. With the phone awake and SeND
  foregrounded, the idle loop stopped and sampled CPU settled to zero. Controlled
  timeline scrolling presented at a 16.6 ms median, compared with about 50 ms
  before the fix. The menu still rebuilt its contents during each drag update,
  producing a 24.9 ms median in that sample. A second change moves only panel
  transforms and retains their child widgets. Device counters then recorded
  roughly 57–60 rendered frames/second during controlled menu gestures, with
  slow-frame build durations down from about 26 ms to 7–8 ms. These are short
  samples, not a guarantee for
  every room or animation. Desktop GPU issue B10 remains open.
- **B55 / B02 / B31, notification-shade return closes the keyboard. Reported.**
  Keep separate from real app backgrounding and deliberate keyboard dismissal.
  Compare retained focus, input connection and IME visibility across shade
  opening/closing. Recheck after B54 without adding a show/hide retry loop.
- **B56 / B52, own replies get recipient highlighting until edited. Reported.**
  The build-132 visual-mention path accepts recipient metadata and formatted
  user links, which can include the reply fallback rather than an authored
  mention. Check normal and edited replies, quoted markup, self-chat and explicit
  mentions. Do not create a self-ping or highlight an ordinary outgoing reply
  merely because its metadata names the reply recipient.
- **B23, Sunup positive diagnostics but no closed-app messages. Reported.**
  A successful test round trip is not proof of real encrypted event delivery or
  process wake-up. Distinguish swiping Recents, process death and Android Force
  stop; inspect the retained pusher, distributor battery access, receiver,
  worker/decryption and notification posting without endpoint tokens or text.
- **B57, mobile single-line message avatar alignment. Reported.**
  The row is top-aligned with fixed avatar/reply offsets. Centre the avatar
  against the appropriate sender/body block for a short message without
  vertically centring it against a tall image, collage or multiline message.
- **B58, cache growth, profile latency and data use. Investigation open.**
  User reports nearly 900 MiB cached and 2.77 GB of mobile traffic since September
  8, with slow profile/avatar loads. These totals alone do not establish duplicate
  fetching or a leak. Separate installed code, Matrix DB, media/temporary files,
  decoded images and the new search index; measure cold/warm requests and cache
  misses. The failed index was not retaining a full text archive. Do not clear
  encryption state, preload every media file or silently weaken cache privacy.

### R19: Download history for local search

The user requested mobile/desktop controls to fetch accessible history. They
chose pausing at the cache limit and offering a larger limit, not an unbounded
archive. The local implementation adds Storage → Download history for search:

- Select the current chat or all joined chats. Confirm before any download.
- Fetch message-event pages directly, decrypt locally and index text/media
  references. Do not download attachment files, mark messages read or bulk-save
  event bodies into the normal Matrix SDK cache.
- Save a per-account, device-local pagination checkpoint. Pause/resume and app
  restart retain the last indexed page. Mobile backgrounding pauses the job.
- Refuse archive writes that would need to evict existing index entries. Offer
  a larger budget and resume the same page. Limits extend to 2048 MiB; the entry
  ceiling scales with larger budgets. Defaults remain 100 MiB/100,000 entries.
- Restore backup sessions needed by the current page when the backup key is
  available. Report events that still cannot be decrypted. Do not import years
  of room keys merely to open a chat.
- Read indexed text directly for search results, including offline pagination.
  Opening source events or media may still require a connection.

The sizing test also exposed a full-table scan when removing FTS rows by their
unindexed event-ID column. Link FTS row IDs to the events table and migrate the
old layout once, keeping event-ID lookups indexed during updates and eviction.

Desktop SQLite benchmarks after compaction, with trigram FTS enabled and 100,000
synthetic Matrix-style IDs, senders, rooms and timestamps:

| ASCII body per message | Database size | Conservative quota charge |
| --- | ---: | ---: |
| 15 characters | 58.1 MiB | 175.9 MiB |
| 200 characters | 127.2 MiB | 257.3 MiB |

These are search-database sizes, not memory usage or total app storage. Matrix's
normal cache, attachment files, installed code and encryption overhead are
separate. Real text distributions and Android SQLCipher/FTS support can change
the result. Quota accounting deliberately reserves more space than the current
database file consumes. This benchmark does not measure real download speed.

Controller, native quota/migration, browser-worker and mobile/desktop widget tests
cover the new paths. The integration fixture checks event-only pagination,
absence of media keys and local search without extra event fetches. No real
account's full archive has been downloaded as a test; encrypted recovery and
large-room completion still need device coverage.

Final local checks: 789 Flutter tests passed with four skips, analysis and
formatting were clean, and Linux, Android and web release builds passed. The
Android preview was installed in place with the existing signing identity and
installer code 2132. Storage shows the new controls and the downloader remains
idle. No commit, push, CI publication or server deployment was performed.

## Earlier release records

Collected 2026-10-10. Published as Latest in 0.9.39+126, with Deltie's PWA and
download mirror updated. Device reports remain separate from automated checks.

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
- B23: Sunup uses Mozilla Autopush, not ntfy. Its Matrix adapter is deployed in
  Deltie's existing loopback Web Push worker. The operator deployed it on
  2026-10-10; source hashes, service health and the public route were verified.
  Actual Sunup delivery still needs a distributor/device test.

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
- Server helper tests: 46 passed, including 20 Web Push gateway tests.
- Linux packaging tests: 8 passed.
- `git diff --check`: clean.
- Linux, Windows, Android and Web/PWA CI passed on commit `437e0ac`.
- Flatpak build, sandbox launch and publication passed.
- GitHub Latest, Deltie's release manifest and the live PWA report 0.9.39+126.

Automated checks cover formatting/escapes, role recipients, notification targets,
search pagination, keyboard lifecycle, icon lookup, missing-history grouping,
FxTwitter avatar suppression and Sunup forwarding. Native RTC, GPU rendering,
Sunup delivery and affected media files still need device testing.

## Build 127 follow-up (2026-10-11)

- B02/B31: Restore the existing input connection before dismissing it on resume.
  Wait while the language chooser owns the window, and lower the entire layout
  if restoration fails. Extend native visibility detection to older Android and
  use browser viewport geometry for the PWA. Physical-device checks remain open.
- B33: Double-underscore composer preview now matches sent underline formatting.
- B34: Server-room headers/details use channel icons; channel picture controls
  are hidden. Other clients' stored room avatars are retained.
- B35: Settings respects the bottom system safe area, keeping Log out reachable.
- B36: Public receipt privacy no longer disables private unread acknowledgement.
- B37: Headless Android push clients request Offline before their first sync.
- B38: The PWA publishes Offline on visibility/page-hide events and keeps sync
  from advertising Online in the background. Return restores the chosen mode.
  Another active device may keep the account online. Abrupt termination without
  a lifecycle event still relies on the homeserver's timeout.

Local checks: 632 Flutter tests passed with four skips, Chrome visibility and
video-probing tests passed, and the JavaScript notification tests passed.
Linux, Windows, Android and Web/PWA CI passed on commit `ca2aff4`. Flatpak's
sandbox launch and publication passed too. GitHub Latest, Deltie's download
mirror and the live PWA now serve 0.9.39+127.

## Build 128 follow-up (2026-10-11)

- Short profile status bubbles fit their text; longer statuses remain bounded
  and wrap. Width checks cover narrow and wide profile cards.
- Simple Sight's Steam entry defaults to application rather than game.
- Visible online DM rows stay subscribed to the existing activity poller even
  with no current activity. Tests cover repeated empty reads without opening a
  profile, viewport bounds, offline exclusion and subscription disposal.
- The large widget suite is split into 15 feature files. Shared fixtures live
  in `test/support/`; all 102 original registration blocks and the fake backend
  were compared with their originals, allowing only helper-name changes.
- Historical plans and investigations moved to `docs/archive/`; references
  were repaired and all Markdown local links checked.

Both one- and two-worker local runs passed 636 tests with four skips. Analysis,
46 server tests, eight packaging tests and 17 JavaScript tests passed. All
platform CI and Flatpak passed on `9160833`; GitHub Latest, Deltie's mirror and
the PWA now serve 0.9.39+128. No local package was installed.
Measured timings are in [CI performance](ci-performance.md).

## Keyboard follow-up (2026-10-13, unreleased)

B02/B31 remain open for a physical-device retest. Gboard's space-hold language
picker still caused keyboard flashing, and stale composer space persisted on
resume after build 128.

- Focus-only transitions no longer run keyboard recovery or send show/hide
  commands. The composer, draft and input connection stay mounted.
- Real background/resume remembers the last editor even if the OS parks focus
  before the background callback. Restoration is attempted once, without a
  timed hide/unfocus fallback. User interaction cancels reopening, not layout
  repair.
- Android observes current IME geometry and animations through an owned view,
  without replacing Flutter's inset handlers. Resume requests fresh insets and
  layout. Stable measurements correct stale keyboard space and retain system
  navigation padding and interface scaling.
- PWA geometry follows the visual viewport and refreshes canvas measurements
  on return. Already-resized canvases do not lose keyboard space twice. If the
  browser declines reopening, the same editor/draft remains and layout lowers.

Local checks: 645 Flutter tests passed with four skips, five Chrome tests and
20 JavaScript tests passed, analysis/formatting were clean, and Android debug
Kotlin compilation passed. No phone was attached. Gboard, other Android IMEs
and installed iOS/Android PWAs still need repeated language-switch and resume
checks. No version/build change, push or release was made for this pass.

## Intake 2026-10-26

Baseline: 0.9.40+130, commit `bccc1c1`. The initial changes shipped in 0.9.41+131.
Existing bug IDs are retained; new IDs start after B38. The investigation notes
below describe the starting code, not the current implementation.

### Build 132 follow-up

- Mention styling includes the sender's own messages and self-chats, separate
  from notification policy. Malformed recipient metadata cannot crash mapping.
- Queued sends keep the ordinary Send button without queue snackbars.
- The new text-index default is 100 MiB. A persistent 80% warning survives a
  large incoming batch that triggers eviction. Index controls offer retry after
  failed storage opens. Existing enabled 50 MiB budgets are preserved.
- Index writes coalesce into batches, totals update incrementally, and backend
  listeners no longer refresh every row when only index statistics change.
- Server dragging replaces the rail's folder-management button. One-second
  holds followed by movement drag; stationary holds retain context menus.
  Centre drops create folders, edge drops reorder, and changes remain personal.
- Message emoji/stickers open a large preview with alias, pack and account-add
  action. Stock emoji retain selectable text and show their catalogue alias.
- A brief Pixel 8 / Android 17 session reproduced the swipe failure after the
  keyboard closed while focus remained. Navigation now excludes the editor's
  actual bounds rather than most of the screen. No messages were sent or app
  data changed during the test. Private screenshots/traces are not published.
- Release-app traces lacked Flutter frame timing and CPU scheduling samples.
  They do not prove a GPU cause for low FPS. Android shell profiling is enabled
  for future approved measurements without making release builds debuggable.
- Local validation: 765 Flutter tests passed with four skips, static analysis
  and formatting were clean, and the Chromium index test covered metadata-only
  storage, edits, redactions, isolation, restart, warning acknowledgement and
  clearing without media requests. Physical-device performance remains open.

### Build 131 implementation

- **B23 / R12, notifications:** Notifications now has Settings and Diagnostics
  tabs. Android can test gateway-to-receiver delivery, then request a local
  notification; browser and local tests remain separate. Reports show saved
  registration, pusher, receiver and worker stages without private endpoints.
  Restoring an already registered distributor no longer registers it again.
  A temporary Mozilla Autopush channel completed a round trip through the
  deployed Deltie gateway and was unregistered afterwards. No user's phone was
  notified. This proves that gateway path, not delivery on the reporting phone.
  The synthetic test cannot prove encrypted-message decryption or OS display.
- **B39 / B40 / B02 / B31, editing:** Selection toolbars remain inside the
  editor's tap region. While editing, navigation drags start at the edge rather
  than competing with selection handles. Rendered emoji carets snap to the
  shortcode end; backspace removes its closing colon without jumping to the
  beginning. Android reports input-method subtype changes, allowing one
  restoration if switching language actually dismisses the keyboard. Existing
  resume geometry repair remains. Physical Gboard and PWA checks remain open.
- **B41 / B42, attachments:** Mobile pending spoilers have a dark preview and
  hidden-eye indicator. Captions introduce a collage and render above its grid;
  unrelated older attachments are not absorbed across that caption boundary.
- **B43, receipts:** Placement measures the actual rendered text and marker,
  including rich text, emoji and spoilers. Media retains its full width. Markers
  that do not fit move to the relevant sender-group header without changing
  their event ownership. Escape also closes message actions when selectable
  text has consumed the key for its own toolbar.
- **B22 / B44, search and media:** Text indexing is off by default, offered in
  onboarding and a one-time prompt for existing users. Storage settings expose
  its toggle, budget and clear action. The default budget is 50 MiB per account
  on this device, with a 100,000-event ceiling; older index entries are evicted.
  Disabling text indexing removes indexed message bodies, not normal Matrix
  history. Android uses the existing SQLCipher storage setup; other native
  desktops use a private SQLite file. The browser index runs in an IndexedDB
  worker. Decrypted search text remains local and is not separately encrypted
  on desktop or in that browser index.
  Media indexing retains event IDs, room IDs, sender IDs, dates and media types,
  never media bytes or attachment keys. It grows from events fetched during
  sync, reading and search, not a background download of the whole archive.
  Search matches separate words without a phrase-only prefilter. Media browsing
  has its own history cursor, stable thumbnail futures and paged fullscreen
  viewers. Full-size viewer image references are kept only around the current
  item. The index budget is not a limit on Matrix's existing cache or active UI
  memory, and unavailable encryption keys still limit search coverage.
- **B45 / B49, empty activity/history:** Profile history now owns its polling
  subscription; an offline or offscreen DM-row watcher cannot suppress it.
  Reading other profiles is separate from local detection/publication, starts
  without the old 15-second delay, prioritizes open profiles and uses bounded
  concurrent reads. One inaccessible profile no longer delays all users for a
  minute. Completed listening history remains visible offline; live activity
  still obeys presence and expiry. B49 also covers the later report of blank
  activity on both layouts and blank Libre.fm history on mobile profile open.
- **B46, AppImage icon:** About offers user-level desktop integration, installing
  the matching desktop entry and icon with the real AppImage path. GTK's icon
  name and the X11 class hint match the application ID. Run integration again
  after moving the AppImage. KDE taskbar/Alt-Tab validation remains a device check.
- **B47, Libre.fm artwork:** Valid provider artwork is retained in live and
  completed records. An optional missing-cover lookup uses MusicBrainz and Cover
  Art Archive, with artist/album matching, an artwork host allowlist, bounded
  responses, throttling and cached results. The switch explains that artist and
  album names go to those services. No username or Matrix credentials go with
  the lookup. Missing or ambiguous artwork retains a placeholder.
- **B48, Windows Spotify:** Windows previously had process/IPC discovery but no
  music-session reader, and default-type Spotify RPC was classified as a game.
  Spotify RPC is now music. Windows media-session reads supply track, artist,
  playback progress and normalized artwork when the player exposes them. A
  Spotify process without track metadata is an application, not a game. Detection
  remains opt-in; explicit per-program settings still apply. The reader uses a
  fixed, bounded PowerShell/WinRT query, not window-title scraping or Spotify
  network requests. A real Windows playback test is still required.
- **R13, proxy:** Test connection path uses the unsaved dialog values and a
  small Matrix versions request, reporting proxy TCP, SOCKS, TLS and HTTP stages.
  It neither changes active settings nor falls back to a direct connection.
- **R14–R18, personal organisation:** Archive/restore and pin controls are in
  chat menus. Chats and spaces provides archived chats, space ordering and
  personal rail folders. Archived chats stay joined and retain notification
  settings; they do not automatically return on a new message. Favourites and
  frequency counters for emoji, stickers and GIFs sync as bounded, per-installation
  Matrix account data. Logical clocks merge edits/removals and counters avoid
  replay double-counting. Old device-global favourites require an explicit import
  into the current account. These are SeND preferences, not shared space state or
  standard room tags. Account data is visible to the homeserver, not E2EE.
- **B19:** Closed by user clarification. Public Space controls already exist;
  no access rules or encryption settings were changed.
- Tests also exposed a daylight-saving boundary in mobile Yesterday labels;
  they now use calendar dates rather than subtracting 24 hours.

Local validation:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --concurrency=4`: 732 passed, four skipped.
- Real Chromium worker test: opt-in/off, account isolation, edits, redactions,
  restart, clearing and equal-timestamp pagination passed. It made no media or
  external network requests.
- JavaScript notification tests: 20 passed.
- Desktop-entry validation and private temporary-file integration tests passed.
- Dart formatting and `git diff --check` are clean.

No physical phone, Windows desktop or KDE session is attached to this test
environment. No application package or CI build was started.

References for the added integrations:

- [Windows media sessions](https://learn.microsoft.com/en-us/uwp/api/windows.media.control.globalsystemmediatransportcontrolssessionmanager)
- [MusicBrainz request limits](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting)

### Release follow-up, 0.9.41+131

The user authorized CI, web deployment and a Latest release after the local
implementation commit. Publication waits for the matching platform builds.

- Emoji autocomplete starts with one character after `:`. Rank the combined
  custom/Unicode matches by usage before taking three results, so a frequent
  `fir_hangry` can outrank an unused `happy` for `:ha`.
- **B50, notification identity:** foreground and Android background resolution
  both selected the sender avatar. They now share Space/group identity selection;
  only DMs use the sender picture. Missing Space artwork stays generic.
- **B51, queued sends:** the submit guard rejected a second send during an
  upload. Submitting now detaches another draft and puts it in a per-room FIFO.
  Text, attachment groups, GIFs and voice messages retain their target; other
  rooms are independent. Pending jobs are cancelled when the session ends.
- **B52, mention presentation:** room-wide aliases lacked token styling, and
  punctuation after `everyone` prevented outgoing mention metadata. Both paths
  now recognize punctuation boundaries. Recipient pings highlight the whole row,
  including a collage whose caption belongs to a folded member. Explicit empty
  mention metadata remains authoritative, and room permissions still apply.
- Initial CI exposed a missing desktop-entry validator on the Android runner and
  a UTC-midnight fixture crossing a collage's day boundary. Install the validator
  explicitly in the Linux-hosted native test jobs and use a noon fixture.

### Initial investigation

### Open and reopened bugs

- **B23: Sunup notifications still fail. Reopened by user report.**
  `matrixPushGatewayForUnifiedPushEndpoint` routes Mozilla endpoints to Deltie's
  Matrix adapter. `server/web_push.py` forwards event/room IDs to Autopush.
  Existing tests mock forwarding; they do not establish delivery to a phone.
  Trace distributor registration, retained Matrix pusher, selected gateway,
  upstream HTTP result, Android receiver, decryption and notification posting.
  Check foreground, background and process-stopped delivery separately.
  The `aes128gcm` header convention is also used by UnifiedPush common-proxies;
  its presence alone is not evidence of the cause. Do not request or log private
  endpoint capabilities. R12 covers the missing user-visible diagnostic workflow.

- **B39: Mobile Copy/Paste/Select all controls do not work. Reported.**
  The mobile composer uses a TextField with `AdaptiveTextSelectionToolbar`,
  forwarding Flutter's default text actions and adding Paste image separately.
  Audit toolbar callbacks, focus, clipboard permission/gesture requirements and
  selection offsets. Test ordinary text and custom emoji independently on native
  Android and PWA. No device reproduction or universal cause established yet.

- **B40: Custom-emoji backspace removes the leading colon and jumps the caret.**
  Expected: backspace at the end removes the trailing colon and leaves the caret
  there, not at the start. The mobile `_CustomEmojiEditingController` renders an
  emoji image followed by zero-width WidgetSpans for the rest of its shortcode.
  This is a candidate for incorrect visual hit-testing/caret offsets, not a
  confirmed root cause. Mobile does not use desktop's
  `CustomEmojiDeletionFormatter`, whose tests deliberately require whole-token
  deletion. Cover both input paths, IME edits, duplicate emoji and selection;
  do not mistake the desktop formatter tests for mobile coverage.

- **B41: Spoiler state is missing from the pre-send image preview.**
  Confirmed code gap on mobile: `_PendingAttachmentPreview` offers a spoiler
  toggle but never draws a spoiler overlay or indicator. Desktop's
  `_PendingAttachmentTile` already draws a dark overlay and hidden-eye icon.
  Mark the pending item clearly without changing its outgoing spoiler metadata.

- **B42: Captions split image collages.**
  Confirmed current behaviour: `MediaAlbumIndex._eligible` explicitly excludes
  captioned attachments, and the existing album tests assert that exclusion.
  Group compatible uploads and put the caption above the grid. Preserve every
  caption, event ID, reply, spoiler and receipt; do not absorb unrelated messages
  into a collage or duplicate the caption on individual cells.

- **B02: Gboard language switching still lowers the keyboard. Reconfirmed.**
  Keep linked resume issue B31 open, but this report specifically reconfirms
  language switching. Build 129's geometry/focus changes did not settle B02.
  The composer already avoids unfocusing in `onEditingComplete`. Inspect actual
  IME/focus transitions and the mobile shell's broad horizontal-drag handler,
  which still calls `unfocus()`. That handler is a lead, not an established
  cause. Existing simulated lifecycle tests are not a Gboard device test.

- **B43: Read-receipt and edited markers relocate or wrap unnecessarily.**
  `ReceiptPlacement` measures plain `message.body` at a fixed 14-point style and
  reserves a guessed 28/90-pixel marker width. Actual rendering includes rich
  spans, custom emoji, spoilers, media and scaled fonts. That measurement mismatch
  can explain false header relocation; the reported cases still need reproducing.
  Use consistent real layout constraints for placement. Cover edited/read
  combinations, exact-width endings, sender groups, captions, albums and text
  scaling, without changing which message owns a receipt.

### Further reports, 2026-10-26

- **B22: Chat search remains slow or unreliable. Reopened.**
  `_searchRoomHistory` calls Matrix SDK 10.1.0's `Room.searchEvents`. A new
  query walks the local event database, then fetches history and decrypts events
  sequentially. This is a history scan, not an indexed text search. SeND's
  parsed terms are joined into one substring for the SDK before the later
  all-terms filter, which can also miss non-contiguous matches in older history.
  Existing cursor tests cover pagination and cancellation, not large-room
  latency or search completeness across unavailable encryption keys.

- **B44: Browsing and scrolling through chat media is rough.**
  The Media tab filters `backend.messages` and loads older items through the
  live timeline's `loadMoreHistory`. Its results therefore depend on the chat's
  current, bounded history window. Desktop and mobile fullscreen galleries use
  fixed media lists, without their own history cursor. `_MediaResult` creates a
  new thumbnail future during every build; caching may avoid a network fetch,
  but the asynchronous work still restarts. Missing dimensions or a suitable
  thumbnail cause the grid to show an icon instead of a preview. These are
  confirmed implementation constraints; frame-time measurements are still needed.

- **B45: Libre.fm last-listened history disappears when the person goes offline.**
  Reported, cause not yet reproduced. The controller is intended to preserve
  durable `lastfm_recent.device.*` profile fields for both providers and remove
  only live activity on offline transitions. `LastFmRecentBar` has no presence
  gate, and the existing Libre.fm test preserves history after going offline.
  Check a fresh remote profile read, successful durable publication, completed
  scrobble parsing, shutdown before a pending history write completes, and
  provider changes. Distinguish a completed last-listened track from an active
  now-playing track, which is supposed to disappear offline. Do not keep live
  activity visible as a workaround.

- **B19: Making a Space public. Resolved by user clarification.**
  Current code exposes Space settings → Basic → Access and discovery → Who can
  join? → Anyone, with a separate public-directory switch. Controls depend on
  permissions and successful settings loading. A failed directory-visibility
  lookup currently fails the whole access-settings load, even though join rules
  are separate. Check reachability, real permissions, error states and saving on
  both layouts. Public Space membership must not silently make every child
  channel public or change encryption/history access.

- **B46: KDE Wayland shows a generic icon for the AppImage.**
  The GTK application ID is `net.deltie.deltiecord`, matching the bundled
  desktop filename and icon name. Packaging includes the icon and desktop file
  inside the AppImage, but the launcher only sets library paths and does not
  register either with the host desktop. Missing desktop integration is the
  leading explanation; verify the actual KDE window app ID and installed
  desktop entry before closing the report.
  Offer user-level application-menu integration with a persistent icon and an
  Exec path pointing to the real AppImage, not its temporary mount. Preserve
  the ID match and check the older `StartupWMClass=deltiecord` on X11 too.
  Validate taskbar, Alt-Tab and launcher icons, including after an AppImage
  update or move. A window-icon call alone does not establish KDE integration.

- **B47: Libre.fm has no album artwork.**
  Confirmed implementation gap: both Libre.fm feed parsing and profile record
  parsing explicitly discard artwork. This applies to live music and completed
  history. Add a bounded artwork path for provider-supplied URLs when available,
  with appropriate host validation and browser support. A possible fallback is
  MusicBrainz release/release-group identification plus Cover Art Archive.
  Album-name matching can be ambiguous; use release IDs where available, cache
  results and misses, and keep a placeholder when no reliable cover is found.
  Additional provider lookups need a clear privacy choice. Do not silently send
  Libre.fm listening history to Last.fm or accept arbitrary artwork URLs.

### Search and media options

1. **Improve the existing browser first.** Give search and media their own
   pagination state; retain results and scroll anchors across room/UI updates;
   cache thumbnail futures by event/media identity. Use stable placeholders,
   thumbnails sized for their cells, and bounded prefetch of nearby items.
   Fetch full images on demand and keep videos paused until opened. This helps
   browsing but does not make repeated history scans fast.
2. **Add a persistent local index. Recommended foundation.** Index messages and
   attachment metadata incrementally after sync/decryption, with edits and
   redactions applied by event ID. Search the index immediately and backfill
   older history in bounded batches. Use an encrypted native index where
   supported and a suitable browser store/worker, scoped to the account with
   explicit cleanup. Keep decrypted search content on the device. A shared
   media index can feed the grid and both fullscreen viewers, with paging in
   either direction and stable event anchors independent of the live timeline.
   Show history coverage while indexing; a fresh device cannot instantly search
   encrypted messages it has never downloaded or decrypted.
3. **Use homeserver text search for unencrypted rooms where supported.** This
   can complement the local index for old public history. It cannot replace
   device-side search of encrypted conversations, and server capabilities vary.

Profile with a large room containing text, albums, GIFs and videos. Measure
first useful results, query latency after indexing, frame times during scrolling,
thumbnail bytes and cache growth. Include cold and warm cache, missing keys,
edits/redactions, slow network and mobile memory pressure. Set budgets from those
measurements; do not promise Discord-equivalent performance from widget changes
alone. Retain encrypted-media integrity checks when optimizing loading.

### Requests

- **R12: Notification test and a Diagnostics tab within Notifications.**
  Existing controls include local system notification tests, browser push tests
  and browser-setup dialogs. Native `UnifiedPush.testPush` and
  `DeltiecordPushDiagnostics` already support a gateway round trip, but that
  workflow is not exposed as the requested Notifications diagnostics tab.
  Provide one entry point with stage results and timestamps for OS permission,
  distributor, pusher, gateway, receiver, decryption and posting. Distinguish
  local rendering tests from real push delivery. Exclude tokens, endpoint
  capabilities, message bodies, recovery material and media keys from reports.

- **R13: Test connection path in the SOCKS5 dialog.**
  Currently no test action exists. Test the values currently entered without
  saving, restarting or changing the application's active proxy snapshot.
  Report proxy lookup, TCP connection, SOCKS negotiation/authentication, target
  tunnel, TLS and a small Matrix HTTP request. Never fall back directly or
  expose credentials. Browser/PWA limitations still apply.

- **R14: Archive chats.**
  Add an archive view and restore action. Archiving must not leave/forget a
  Matrix room or delete history. Define unread, search and new-message behaviour
  before implementation. No archive UI or matching room-list preference was
  found in the current client.

- **R15: Folders grouping servers/spaces in the space bar.**
  User confirmed this means rail folders, not channel categories within a server.
  Treat these as personal organisation; do not rewrite shared server hierarchy
  or permissions. Keep folder creation, renaming and moving spaces usable on
  mobile as well as desktop.

- **R16: Reorder spaces in the space bar.**
  Current `MatrixBackend.spaces` maps joined spaces without a personal saved
  order. Keep this separate from already implemented ordering of channels within
  a space. Persist the user's rail order, including folder membership.

- **R17: Pin DMs above ordinary chats.**
  Current message and video-stream pinning are different features. Use Matrix
  `m.favourite` room tags where appropriate, with ordering among pinned DMs.
  Preserve normal activity ordering below the pinned group.

- **R18: Sync favourites and frequently used emoji, GIFs and stickers.**
  Feasible through account-scoped Matrix account data. Current
  `FavouriteReactionsStore` keeps emoji/sticker favourites and usage counters in
  local JSON or browser private storage. `GifService` keeps local GIF favourites;
  no GIF-frequency counter was found. These singleton/local stores are not yet
  partitioned for a cross-account migration.
  Scope data by account before importing old local lists. Merge offline edits
  and removals; use bounded per-device counters and batched writes to avoid
  clobbering another device's usage or double-counting replayed sync events.
  Sync media references rather than reuploading binaries. Account data is not
  room-public, but ordinary account-data JSON is not E2EE by default.

### Already shipped: zsync

Zsync/AppImage delta updates shipped in build 129 and remain in 0.9.40+130.
The AppImage bundles a small zsync client, uses SeND's HTTPS/SOCKS-aware loopback
relay, checks the reconstructed image against manifest SHA-256, and falls back
to a verified full download. Activation is explicit and keeps a rollback copy.
CI publishes versioned `.AppImage.zsync` files and the mirror's latest pointer.
This does not make old AppImages without the updater self-update retroactively.

### Initial investigation checks

- Code paths inspected for every report/request above. Labels distinguish code
  gaps and existing behaviour from unconfirmed device faults.
- 29 focused Flutter tests passed: custom-emoji deletion/completion, album
  grouping, composer focus/lifecycle and UnifiedPush routing. These existing
  tests do not reproduce the reported phone behaviour; some encode behaviour
  that this intake asks to change.
- A further 19 existing Libre.fm, last-listened history and search tests passed.
  They do not reproduce the reported remote-profile disappearance or establish
  performance on large chat histories. Artwork exclusion is currently asserted
  by a test, so supporting Libre.fm artwork requires changing that policy too.
- No production notification was sent, server changed, app behaviour modified,
  build started, version bumped, commit made or push performed for this intake.

Protocol references:

- [Matrix account data](https://spec.matrix.org/latest/client-server-api/#client-config)
- [Matrix room tags](https://spec.matrix.org/latest/client-server-api/#room-tagging)
- [Sunup distributor](https://unifiedpush.org/users/distributors/)
- [UnifiedPush gateway forwarding](https://github.com/UnifiedPush/common-proxies/blob/main/handler.go)
- [KDE desktop entries](https://develop.kde.org/docs/features/desktop-file/)
- [GTK/KDE Wayland app-ID matching](https://bugzilla.mozilla.org/show_bug.cgi?id=1826330)
- [Cover Art Archive API](https://musicbrainz.org/doc/Cover_Art_Archive/API)
