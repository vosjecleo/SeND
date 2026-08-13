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
