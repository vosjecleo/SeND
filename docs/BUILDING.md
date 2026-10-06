# Building SeND from source

The authoritative project version is in `pubspec.yaml`. Release CI currently
pins Flutter 3.47.0 and Rust 1.97.1. Using those versions is recommended when
reproducing an official build.

Clone the repository and fetch Dart dependencies:

```sh
git clone https://github.com/vosjecleo/SeND.git
cd SeND
flutter pub get
```

Before packaging a change, run the same basic validation used by CI:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
```

## Linux source build

Linux builds require a C/C++ toolchain, CMake, Ninja, pkg-config, Rust, and the
development packages for GTK 3, libsecret, PulseAudio, ALSA, libv4l, libmpv,
and PipeWire. Debian 12 package names and the exact CI setup are documented in
[the Linux workflow](../.github/workflows/linux.yml).

For a local development build:

```sh
flutter run -d linux
```

For reproducible release packages, use the packaging entry point instead of
calling `flutter build` directly:

```sh
FLUTTER_BIN="$(command -v flutter)" packaging/build-release.sh
```

It builds a Linux release, validates required native libraries, and writes the
Debian package, AppImage, checksums, and build metadata to `dist/`. On an Arch
host with `makepkg`, it also produces the native Arch package. The release
scripts apply the Rust FFI retention flag required by the current E2EE stack and
verify downloaded AppImage tooling against pinned SHA-256 hashes.

The official AppImage and Debian package are built in Debian 12 to retain a
glibc 2.36 baseline. Building them on a newer rolling distribution may produce
binaries that cannot run on Debian 12.

More packaging details are in [packaging/README.md](../packaging/README.md).

## Windows source build

Install Flutter 3.47.0, Git, Rust 1.97.1, and Visual Studio with the **Desktop
development with C++** workload. Then run in PowerShell:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
flutter build windows --release
```

The complete runnable directory is written to
`build\windows\x64\runner\Release`. The executable is not standalone. Inno
Setup 6 can build the per-user installer using
`packaging\windows\deltiecord.iss`; the exact automated process is in
[the Windows workflow](../.github/workflows/windows.yml).

Further Windows notes are available in [docs/WINDOWS.md](WINDOWS.md).

## Android source build

Install the Android SDK, Android SDK command-line/build tools, Java 17, Flutter
3.47.0, and Rust 1.97.1. Add the Android Rust targets used by the E2EE native
library, then run:

```sh
flutter pub get
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

The APK is written below `build/app/outputs/flutter-apk/` and the AAB below
`build/app/outputs/bundle/release/`. The exact pinned CI setup is documented in
[the Android workflow](../.github/workflows/android.yml). See
[Android implementation and testing notes](ANDROID.md) before distributing
a build. Release signing credentials must be supplied outside the repository;
an unconfigured local build falls back to Android's debug identity for developer
testing and must not be published as an upgradeable release.

## Web build

Run `bash packaging/build-web.sh` from the repository root. It builds the pinned
crypto bindings and Flutter web app, then writes a web archive to `dist/`.
See [Web/PWA deployment](web-deployment.md) for local serving, security headers
and hosting requirements.
