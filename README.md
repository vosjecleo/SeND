# Deltiecord

Deltiecord is a lightweight Matrix client with a compact, old-school desktop
interface. It is built with Flutter and the Matrix Dart SDK so the application
and backend architecture can later be reused on Android.

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

The current UI is deliberately minimal. Rich messaging, MatrixRTC voice rooms,
administration, and customization are staged in the milestones below.

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

### v0.2 — Functioning base app (current)

`0.2` is the first complete everyday messaging baseline.

- [x] Keep keyboard focus in the message composer when opening or changing a
  conversation and after sending, so typing can begin immediately.

- Compose plain text and rich text with a compact WYSIWYG editor: bold, italic,
  underline, strikethrough, inline code, code blocks, quotes, links, lists, and
  spoilers, while preserving a plain-text fallback.
- Matrix-native user and room mentions with autocomplete, keyboard navigation,
  pills/highlighting, and correct notification semantics.
- Send, receive, preview, download, save, and open images, video, audio, and
  general files. Images and videos may be marked as spoilers before sending.
- Generate safe thumbnails, expose upload/download progress, validate file
  limits, and provide retry/cancel behavior without freezing the timeline.
- Display replies cleanly and support creating replies from the timeline.
- Edit and delete/redact the user's own messages, with unobtrusive edited and
  deleted indicators.
- Add, remove, and summarize emoji reactions.
- Maintain accurate unread counts, highlights, read markers, receipts, and a
  jump-to-first-unread affordance.
- Queue sending state visibly and distinguish pending, sent, failed, and retrying
  events without duplicating messages.
- Provide basic desktop notifications with per-room muting and no sensitive
  plaintext leakage when notification previews are disabled.
- Handle common timeline events gracefully instead of displaying raw or
  “unknown event” placeholders.

Promotion gate: text and media conversations must work consistently between
Deltiecord and established Matrix clients in both encrypted and unencrypted
rooms.

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

### v0.4 — UI, UX, and customization

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

### v0.5 — Roles, permissions, and room management

`0.5` makes server and room administration understandable without hiding Matrix
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

### Later v0.x — Hardening and platform work

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
