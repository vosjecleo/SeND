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

The current UI is deliberately minimal. Spaces, the Home DM view, richer
messages, and MatrixRTC voice rooms are post-V0 milestones.

## Roadmap

Deltiecord uses the `0.1.x` line as an active testing ground. Features may be
rough there, but changes must remain testable and must not compromise Matrix
interoperability or encrypted account data.

- **v0.1 — Testing grounds:** validate the Matrix foundation, E2EE recovery,
  Spaces, DMs, timelines, and rapid UX experiments.
- **v0.2 — Functioning base app:** dependable everyday text chat, history,
  replies, edits, reactions, media, unread state, and notifications.
- **v0.3 — Grand features:** all major desired capabilities implemented,
  including voice-room and MatrixRTC foundations.
- **v0.4 — UI/UX rough-complete:** settings, interface polish, density and
  layout customization, accessibility, and coherent desktop workflows.
- **v0.5 — Roles and administration:** member/mod/admin presentation,
  permissions, correctly disabled controls, and Space/group creation and
  management.
- **Later v0.x — Stabilization:** milestones will be defined from real-world
  testing and remaining platform work.
- **v1.0 — Stable desktop release:** every agreed desktop feature implemented,
  interoperable, tested, and reliable enough for general use.

Android remains a shared-architecture target after the desktop application is
stable enough that its backend and interaction model are worth carrying over.
