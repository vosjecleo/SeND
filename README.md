# Deltiecord

Deltiecord is a lightweight Matrix client with a compact, old-school desktop
interface. It is built with Flutter and the Matrix Dart SDK so the application
and backend architecture can later be reused on Android.

Deltiecord is free software licensed under the GNU Affero General Public
License v3.0 or later. See `LICENSE`; third-party acknowledgements and license
links are maintained in `CREDITS.md`.

## V0 features

- Configurable Matrix homeserver and password login
- Persistent SDK session and encrypted-room state
- Joined-room list with unread counts
- Live room timelines and plain-text sending
- End-to-end encrypted room support through the Matrix SDK
- Device authorization through Matrix recovery keys/security passphrases
- Cross-signing and encrypted key-backup status with non-destructive repair
- First-time secure-secret-storage setup with recovery-key confirmation
- Loading, startup, authentication, timeline, and sending error states
- Matrix-independent widget/backend boundary

Session data is stored outside the repository in the platform application-data
directory. On Linux, Deltiecord applies owner-only permissions to its data
directory and database. Passwords are never stored by the application.

### Encryption trust behavior

Deltiecord delivers room keys to every non-blocked device in an encrypted room,
matching the usability expected of a general chat client. Device verification
and cross-signing status remain visible, but an unverified recipient device is
not silently excluded from new messages. Explicitly blocked devices never
receive keys. Existing outbound sessions are rotated once per room after launch
so changes in eligible devices take effect before the next message is sent.

## Development

Flutter 3.47 or newer is recommended.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

Linux desktop builds require Flutter's standard Linux toolchain, including
Clang, CMake, Ninja, pkg-config, and GTK development libraries.

## Architecture

- `lib/backend/` contains the UI-facing backend contract.
- `lib/matrix/` adapts the Matrix SDK, persistence, sync, timelines, and E2EE.
- `lib/models/` contains SDK-independent view models.
- `lib/ui/` contains Flutter widgets only.

The current v0.9 beta provides the complete agreed desktop feature set: Matrix
text/media messaging and E2EE, bounded historical timelines, extensible
profiles, configurable desktop interaction, and MatrixRTC voice/video/screen
sharing. Remaining work toward v1 is validation, bug fixing, performance,
security review, and distribution hardening.

## Roadmap

Deltiecord uses the `0.1.x` line as an active testing ground. Features may be
rough there, but changes must remain testable and must not compromise Matrix
interoperability or encrypted account data. A milestone is reached only when
its features work in encrypted and unencrypted rooms, survive an application
restart, have useful failure states, and pass analysis and automated tests.

### v0.1 — Testing grounds (complete in v0.1.9)

The purpose of `0.1.x` is to prove the foundation while the application is
still cheap to change.

- [x] Stable login, logout, session restoration, sync, and local encrypted
  storage.
- [x] Recovery-key/security-passphrase account recovery, cross-signing, device
  authorization, and encrypted key backup.
- [x] Reliable decryption of live events, paginated history, and room-list
  previews.
- [x] Reliable encrypted and unencrypted text sending, with visible send
  failures.
- [x] Spaces as the server rail; Space children as channels; Home limited to DMs
  and group chats.
- [x] Compact, scrollable message history with avatars, timestamps, reply
  context, unread badges, and read receipts.
- [x] Room, DM, group-chat, user, and Space avatars with sensible fallbacks.
- [x] Cleanup of the backend/UI boundary so later media, RTC, and Android work do
  not leak Matrix SDK objects into widgets.

Promotion gate: **passed by v0.1.9.** Ordinary text conversations are suitable
for daily testing, with no known bug that loses a session, sends undecryptable
messages, corrupts encryption state, or prevents history from loading. New
release-blocking regressions discovered in broader testing must be fixed before
the first `0.2.x` build rather than carried forward as accepted behavior.

### v0.2 — Functioning base app (complete in v0.2.14)

`0.2` is the first complete everyday messaging baseline.

- [x] Keep keyboard focus in the message composer when opening or changing a
  conversation and after sending, so typing can begin immediately.

- [x] Compose plain text and rich text using familiar inline markup: bold,
  italic, underline, strikethrough, inline code, code blocks, quotes, links,
  lists, and spoilers, while preserving a plain-text fallback.
- [x] Send and render interoperable `org.matrix.custom.html` with a plaintext
  fallback, including revealable standard `data-mx-spoiler` content.
- [x] Matrix-native user mentions with autocomplete, keyboard navigation,
  pills/highlighting, and correct notification semantics.
- [x] Add room-name mention autocomplete as interoperable Matrix room links;
  typed `@room` emits the correct room-wide notification metadata.
- [x] Autocomplete room members to full Matrix user IDs and emit `m.mentions`
  notification metadata, including reply and `@room` semantics.
- [x] Send, receive, preview, download, save, and open images, video, audio, and
  general files. Images and videos may be marked as spoilers before sending.
- [x] Stream unencrypted and encrypted video in-chat using authenticated HTTP
  ranges; encrypted AES-CTR media is decrypted per range through a loopback-only
  proxy instead of downloading the complete file before playback.
- [x] Provide safe thumbnails, non-blocking transfer feedback, homeserver-limit
  validation, and retry/removal for failed sends without freezing the timeline.
- [x] Display replies cleanly and support creating replies from the timeline.
- [x] Edit and delete/redact the user's own messages, with unobtrusive edited and
  deleted indicators.
- [x] Add, remove, and summarize emoji reactions.
- [x] Maintain accurate unread counts, highlights, read markers, receipts, and a
  jump-to-first-unread affordance.
- [x] Queue sending state visibly and distinguish pending, sent, failed, and retrying
  events without duplicating messages.
- [x] Provide useful desktop notifications containing decrypted message content,
  with per-room muting.
- [x] Add a synced notification-preview privacy preference and suppress
  plaintext when previews are disabled.
- [x] Handle common timeline events gracefully instead of displaying raw or
  “unknown event” placeholders.

Promotion gate: **passed by v0.2.14.** Everyday text and media messaging is a
stable baseline, including encrypted media interoperability, streaming video,
rich messages, replies, reactions, edits, redactions, mentions, unread state,
notifications, and recoverable send failures. Byte-level transfer meters and
hard network aborts remain valid later refinements, not blockers for v0.2.

### v0.3 — Major communication features

`0.3` implements the large user-facing capabilities before the settings and
administration passes.

- Introduce interoperable voice rooms backed by Matrix room state/account data,
  without inventing an incompatible room protocol.
- Integrate MatrixRTC for one-click join/leave, microphone selection, mute,
  speaking indicators, and a persistent list of connected participants.
- Keep voice rooms separate from text channels and do not expose their backing
  event timeline in the normal Deltiecord interface.
- Stabilize direct calls and group RTC behavior, reconnects, device changes,
  permissions, and clear failure recovery.
- Add GIF search/sending, stickers, emoji selection, custom emoji where Matrix
  supports it, and restrained link/media previews.
- Add message search, pinned messages, member lists, typing indicators, presence,
  and practical room discovery/invite/join flows.
- Support nested Spaces and optional channel categories without making simple
  Spaces cumbersome.

Promotion gate: every major planned communication feature exists and has a
usable end-to-end flow; remaining work is primarily UX depth, administration,
and hardening.

### v0.4 — UI, UX, customization, and management

`0.4` gives all implemented features coherent desktop workflows and their first
complete design pass.

- Add a proper settings area for account, devices, encryption, audio/video,
  notifications, appearance, accessibility, storage, and advanced diagnostics.
- Provide compact/cozy density choices, font scaling, panel sizing, reduced
  motion, keyboard shortcuts, and accessible focus/contrast behavior.
- Make the three-column desktop layout responsive without turning it into an
  oversized mobile-first interface.
- Add optional native GTK title-bar replacement/hiding and remember window size,
  position, maximized state, and panel widths.
- Refine loading, empty, offline, reconnecting, permission-denied, and destructive
  confirmation states throughout the client.
- Complete the original Deltiecord visual identity: old desktop-software/Y2K
  character, restrained animation, dense typography, and no copied Discord
  branding or assets.
- Beginning with **v0.4.1**, fold the former v0.5 administration roadmap into
  this series: richer account/profile, device, privacy, notification, colour,
  font, title-bar, and About settings alongside permission-aware management.
- Make server and room administration understandable without hiding Matrix
  power levels behind misleading Discord terminology.

- Present practical member/moderator/admin roles derived from Matrix power levels
  while retaining accurate permission details where needed.
- Disable or hide controls the current user cannot use, explain why, and update
  them immediately when power levels change.
- Create and configure DMs, group chats, rooms, Spaces, text channels, and voice
  rooms; invite, remove, ban, unban, kick, mute, and change member permissions.
- Configure names, topics, avatars, aliases, join rules, history visibility,
  encryption, guest access, federation-related options exposed by the server,
  and notification defaults.
- Reorder Space children/channels and manage categories/nesting without emitting
  non-interoperable state.
- Add safety rails and confirmations for encryption changes, room upgrades,
  destructive moderation, ownership transfer, and leaving the last-admin role.

There is no separate v0.5 milestone. These capabilities now ship incrementally
as v0.4.x so the design and management workflows evolve together.

### v0.9 — Feature-complete desktop beta

- [x] Searchable local emoji and colon completion, arbitrary key bindings,
  private per-room drafts, drag/drop and clipboard attachments.
- [x] Extensible Matrix profiles, blocked-user controls, outgoing read-state
  indicators, actionable desktop notifications, and complete room headers.
- [x] Bounded 30-event timeline paging, stable visual anchoring, event-centred
  search/pin/reply navigation, and Jump to Present.
- [x] Safe media context actions and a zoomable, keyboard-navigable in-client
  image/video viewer.
- [x] MatrixRTC voice, deafen, local participant volume/mute, remembered media
  devices, camera grids, pinning, and explicit portal-based screen sharing.
- [x] Offline draft retention and idempotent queued text/media retry after
  reconnect.

The automated desktop gate covers models, services, widgets, timeline-window
policy, media ranges, shortcuts, drafts, emoji, profile presentation, receipts,
and RTC state. Multi-user camera and Wayland portal behavior must also be
retested on the intended machines for each beta package because CI cannot grant
real microphones, cameras, or portal screen-capture sessions.

### Post-v0.9 — Hardening and platform work

- Federation, slow-network, offline, large-room, long-history, and large-media
  stress testing.
- Database migration, cache repair, backup/restore, diagnostics export with
  secret redaction, crash recovery, and actionable logging.
- Performance, memory, startup time, media-cache limits, battery, and bandwidth
  work.
- Accessibility audit, localization readiness, packaging, update delivery, and
  repeatable release builds.
- Security and privacy review covering token storage, media handling, URL opening,
  notifications, logs, and dependency updates.
- Android UI adaptation using the same backend/models, followed by Android
  notifications, sharing, media permissions, background sync, and RTC testing.

### v1.0 — Stable desktop release

The Linux desktop client is feature-complete for the agreed scope, interoperates
cleanly with Synapse and established Matrix clients, and has no known critical
session, encryption, message-loss, or RTC defects. Installation and upgrades are
documented and reproducible; core workflows have automated coverage; recovery
and failure behavior have been tested with real accounts; and the UI is stable
enough that normal updates do not repeatedly disrupt established workflows.

Android remains a shared-architecture target after the desktop application is
stable enough that its backend and interaction model are worth carrying over.
