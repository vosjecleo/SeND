# Installing SeND

Voice-message recording (build 104 onward) needs a microphone and OS/browser
permission. On Linux, install `ffmpeg` and the PulseAudio client tools `parecord`
and `pactl` (`pulseaudio-utils` on Debian/Ubuntu, `libpulse` on Arch). PipeWire's
PulseAudio compatibility service is supported. Packaged dependencies include
these tools; standalone AppImage users must provide them on the host.

The current published release is SeND 0.9.35 build 109 for Android,
x86-64 Windows, Linux, and Web/PWA. It marks feature-scope completion, not a
stable-release certification. See [1.0 readiness](docs/RELEASE_READINESS.md).
Download official builds from the [SeND releases page](https://deltie.net/SeND)
or the [published GitHub releases](https://github.com/vosjecleo/SeND/releases/latest).

The filename examples below target **SeND 0.9.35+109**. Existing
accounts survive the rename; the internal `deltiecord` executable/package name
is retained for compatibility; new Linux packages also provide a `SeND` launcher.
See [rename and update notes](docs/build-108-send.md).
Update publishing and viewing clients to build 109 together for independent
game/music/history slots; build 108 does not read the new device-owned records.

Before installing a downloaded build, verify it against the included
`SHA256SUMS` file:

```sh
sha256sum -c SHA256SUMS
```

## Android

Download the APK matching the device architecture. Most current phones use
`SeND-0.9.35+109-android-arm64-v8a.apk`; older 32-bit phones use
`armeabi-v7a`, while `x86_64` is primarily for emulators. Verify
its checksum, allow installation from the browser or file manager when Android
asks, then open the APK. The APK uses SeND's persistent release-signing
identity; v0.9.19 was the first build signed by this identity.
The private keystore and passwords are stored outside the repository. APKs from
builds 62 and 63 used ephemeral identities and require one uninstall before this
first persistently signed build can be installed; later upgrades retain the same
identity.

Android may require microphone, camera, media, and notification permissions as
the corresponding features are used. Notifications can use a separately
installed UnifiedPush distributor. SeND pairs the private endpoint with
the Matrix gateway belonging to the same ntfy server.

The AAB produced by CI is intended for future repository/store distribution and
is not directly installable. Android RTC, encrypted media, screen capture,
notification delivery, suspend/resume, and vendor-specific battery management
still require broader real-device testing.

## Windows

### Installer

Download `SeND-0.9.35+109-windows-x64-setup.exe`, run it, and follow the
installer. A normal per-user installation does not require administrator
privileges. The installer creates a Start Menu entry and can optionally create
a desktop shortcut.

Windows may warn about an unrecognized application because this release is not yet
code-signed. Only continue if the filename and SHA-256 checksum match the
official release.

Upgrading or uninstalling SeND does not delete Matrix sessions or other
per-user application data.

### Portable build

Download `SeND-0.9.35+109-windows-x64-portable.zip`, extract the entire
archive, and run `deltiecord.exe` from the extracted directory. Do not move only
the executable: its accompanying DLLs, plugins, data, and assets are required.

Native Windows behavior still needs broader testing on physical Windows 10 and
11 systems. Please report platform-specific notification, secure-storage,
clipboard, drag-and-drop, audio/video device, screen-sharing, and media-playback
issues.

## Debian, Ubuntu, and Linux Mint

Download `SeND-0.9.35+109-linux-debian-amd64.deb`, open a terminal in its directory, and
install it with APT:

```sh
sudo apt install ./SeND-0.9.35+109-linux-debian-amd64.deb
```

APT installs the package and its declared runtime dependencies. Launch it from
the desktop application menu or run:

```sh
deltiecord
```

Remove the application with:

```sh
sudo apt remove deltiecord
```

Removing the package does not delete per-user Matrix sessions or application
data.

## Arch Linux

Download `SeND-0.9.35+109-linux-arch-x86_64.pkg.tar.zst` and install it with pacman:

```sh
sudo pacman -U ./SeND-0.9.35+109-linux-arch-x86_64.pkg.tar.zst
```

Launch SeND from the application menu or run `deltiecord`. Remove the
package with `sudo pacman -R deltiecord`; user data remains untouched.

## AppImage

The AppImage is useful on other current x86-64 Linux distributions. Download
`SeND-0.9.35+109-linux-appimage-x86_64.AppImage`, make it executable, and launch it:

```sh
chmod +x SeND-0.9.35+109-linux-appimage-x86_64.AppImage
./SeND-0.9.35+109-linux-appimage-x86_64.AppImage
```

The AppImage contains the Flutter application but deliberately relies on some
ABI-sensitive desktop libraries from the host. It requires a reasonably current
GTK 3 Linux system, a working desktop Secret Service for session and E2EE-key
storage, and PulseAudio or PipeWire-Pulse for audio.

On Wayland, screen sharing requires PipeWire, `xdg-desktop-portal`, and a portal
backend for the desktop environment, such as `xdg-desktop-portal-gtk` or
`xdg-desktop-portal-kde`.

## Web/PWA, including iPhone/iPad

Open [chat.deltie.net](https://chat.deltie.net). On iPhone/iPad, use Safari's
Share → Add to Home Screen, then open the installed app. Android and desktop
browsers can use their Install app option. This is the Flutter web target, not
a native macOS/iOS package. Keep your Matrix recovery key before clearing site
data; browser storage can be evicted. Enable notifications from the installed
app's settings and validate delivery on your device.

Password sign-in remains available. **SSO / browser sign-in** discovers what
the chosen homeserver supports; it does not create an identity provider. Device
verification and encryption recovery remain separate. Self-hosters must apply
the [callback hosting safeguards](docs/web-deployment.md) before browser SSO.

See [browser limitations](KNOWN_ISSUES.md) and [deployment](docs/web-deployment.md).

## Application data

SeND stores runtime data in the operating system's normal per-user
application-data and secure-storage locations. Package upgrades and ordinary
uninstallation do not remove that data. Never copy or publish those directories:
they can contain Matrix session and encryption state.

If persisted login or E2EE storage does not work on Linux, first confirm that a
Secret Service provider such as GNOME Keyring or KWallet is installed, unlocked,
and available to the desktop session.

## Building from source

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

### Linux source build

Linux builds require a C/C++ toolchain, CMake, Ninja, pkg-config, Rust, and the
development packages for GTK 3, libsecret, PulseAudio, ALSA, libv4l, libmpv,
and PipeWire. Debian 12 package names and the exact CI setup are documented in
[the Linux workflow](.github/workflows/linux.yml).

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

More packaging details are in [packaging/README.md](packaging/README.md).

### Windows source build

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
[the Windows workflow](.github/workflows/windows.yml).

Further Windows notes are available in [docs/WINDOWS.md](docs/WINDOWS.md).

### Android source build

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
[the Android workflow](.github/workflows/android.yml). See
[Android implementation and testing notes](docs/ANDROID.md) before distributing
a build. Release signing credentials must be supplied outside the repository;
an unconfigured local build falls back to Android's debug identity for developer
testing and must not be published as an upgradeable release.

## Getting help

Check [KNOWN_ISSUES.md](KNOWN_ISSUES.md) before reporting a problem. Useful bug
reports include the operating system and desktop environment, SeND build,
homeserver implementation, whether the room is encrypted, and clear steps that
reproduce the issue. Do not include access tokens, recovery keys, decrypted
messages, encryption keys, or private media URLs in a report.
