# Installing SeND

Download SeND from [deltie.net](https://deltie.net/SeND) or
[GitHub Releases](https://github.com/vosjecleo/SeND/releases/latest).
To use it without a native package, open [chat.deltie.net](https://chat.deltie.net).

Choose your platform:

- [Android](#android)
- [Windows](#windows)
- [Debian, Ubuntu or Linux Mint](#debian-ubuntu-and-linux-mint)
- [Arch Linux](#arch-linux)
- [Flatpak](#flatpak-direct-download-package)
- [AppImage](#appimage)
- [Web app, iPhone or iPad](#webpwa-including-iphoneipad)

For an existing installation, see [upgrading](#upgrading).
Developers can follow [building from source](docs/BUILDING.md).

The filename examples use build **0.9.37+119**. Use the matching filename
from the release you downloaded. SeND is still pre-1.0; check
[known issues](KNOWN_ISSUES.md) for platform limitations.

## Check the download

Compare the file's SHA-256 checksum with its entry in the release's
`SHA256SUMS` file before installing.

On Linux:

```sh
sha256sum SeND-0.9.37+119-linux-appimage-x86_64.AppImage
```

On Windows, use PowerShell:

```powershell
Get-FileHash .\SeND-0.9.37+119-windows-x64-setup.exe -Algorithm SHA256
```

If you downloaded all files listed in `SHA256SUMS`, you can check them together
with `sha256sum -c SHA256SUMS`.

## Android

Download the APK for your device:

- Most current phones: `SeND-0.9.37+119-android-arm64-v8a.apk`.
- Older 32-bit phones: the `armeabi-v7a.apk` file.
- x86-64 devices and emulators: the `x86_64.apk` file.

Open the APK and allow installation from your browser or file manager when
Android asks. The AAB is for store distribution and cannot be installed directly.

SeND requests microphone, camera, media and notification permissions when you
use the corresponding features. For background notifications, install a
UnifiedPush distributor such as ntfy and select it in SeND's notification
settings. See [Android notifications](docs/ANDROID.md#notifications-and-background-operation).

## Windows

### Installer

Run `SeND-0.9.37+119-windows-x64-setup.exe` and follow the instructions.
A normal per-user installation does not require administrator privileges.
It creates a Start Menu entry and offers a desktop shortcut.

Windows may warn that the application is unrecognized because the release is
not code-signed. Continue only if the file and checksum match the official release.

### Portable build

Extract the entire `SeND-0.9.37+119-windows-x64-portable.zip` archive, then
run `deltiecord.exe` inside it. Keep the accompanying DLLs, plugins, data and
assets in place; the executable cannot run alone.

## Debian, Ubuntu, and Linux Mint

Download `SeND-0.9.37+119-linux-debian-amd64.deb`, open a terminal in its directory, and
install it with APT:

```sh
sudo apt install ./SeND-0.9.37+119-linux-debian-amd64.deb
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

Download `SeND-0.9.37+119-linux-arch-x86_64.pkg.tar.zst` and install it with pacman:

```sh
sudo pacman -U ./SeND-0.9.37+119-linux-arch-x86_64.pkg.tar.zst
```

Launch SeND from the application menu or run `deltiecord`. Remove the
package with `sudo pacman -R deltiecord`; user data remains untouched.

## Flatpak (direct-download package)

An x86-64 Flatpak package is published alongside the native Linux
downloads. Install it with `flatpak install --user ./SeND-0.9.37+119-linux-x86_64.flatpak`
and launch with `flatpak run net.deltie.deltiecord`. It downloads a shared GNOME
runtime separately. This is not yet a Flathub listing or an automatic SeND
update repository. See [Flatpak installation and sandbox limitations](packaging/flatpak/README.md),
particularly for desktop game detection and Discord IPC.

## AppImage

The AppImage is useful on other current x86-64 Linux distributions. Download
`SeND-0.9.37+119-linux-appimage-x86_64.AppImage`, make it executable, and launch it:

```sh
chmod +x SeND-0.9.37+119-linux-appimage-x86_64.AppImage
./SeND-0.9.37+119-linux-appimage-x86_64.AppImage
```

The AppImage bundles libmpv, its media dependencies, and Flutter/plugin
dependencies including libepoxy. You do not need to install host libmpv. Matching sources
are a separate optional `SeND-0.9.37+119-appimage-sources.tar.gz` release download;
licence notices are included in the AppImage. Some desktop libraries must come
from the host to match its plugins. The AppImage requires a reasonably current
GTK 3 Linux system, a working desktop Secret Service for session and E2EE-key
storage, and PulseAudio or PipeWire-Pulse for audio.
PipeWire/SPA client libraries must come from the host so they match its modules
and PipeWire-JACK adapter. The AppImage retains a standalone JACK fallback, but
does not bundle an older PipeWire client or a PipeWire-JACK adapter.
Likewise, librsvg comes from the host GTK/SVG icon-loader stack; mixing an old
bundled SVG renderer with newer desktop icon loaders can prevent startup.

## Linux voice recording and screen sharing

Voice-message recording needs a microphone, permission to use it, `ffmpeg`,
and the PulseAudio tools `parecord` and `pactl`. The PulseAudio tools are in
`pulseaudio-utils` on Debian/Ubuntu and `libpulse` on Arch. PipeWire's
PulseAudio compatibility service is supported.

Native packages declare these dependencies. AppImage users must install the
recording tools on the host. Flatpak uses its packaged runtime.

On Wayland, screen sharing also needs PipeWire, `xdg-desktop-portal`, and a
portal backend for your desktop, such as `xdg-desktop-portal-gtk` or
`xdg-desktop-portal-kde`.

## Web/PWA, including iPhone/iPad

Open [chat.deltie.net](https://chat.deltie.net).

- On iPhone or iPad, open the site in Safari, choose **Share → Add to Home
  Screen**, then launch the installed app.
- On Android or desktop, use the browser's **Install app** option, or use the
  site in a browser tab.

Enable notifications in the installed app's settings. iOS Web Push requires
iOS 16.4 or later and Home Screen installation. Check delivery on your device;
see the [iOS notification checklist](docs/ios-push-checklist.md) if it fails.

Keep your Matrix recovery key somewhere safe. Clearing site data, private
browsing or browser storage eviction can remove your local session and keys.

Browser sign-in is available when your homeserver supports SSO/OIDC. It does
not replace encryption-device verification or recovery. Self-hosters must
apply the [callback security rules](docs/web-deployment.md) before enabling SSO.

## Upgrading

Install the new package over the existing installation. Ordinary package
upgrades and uninstalls leave per-user application data in place; do not delete
that data to resolve an upgrade error.

SeND was previously called Deltiecord. The rename preserves accounts, settings
and encrypted sessions. Some package names, executable names and application
IDs still use `deltiecord` for compatibility. Linux packages also provide a
`SeND` launcher.

- **Android:** current APKs use a persistent release-signing identity, introduced
  in v0.9.19. Builds 62 and 63 used temporary signing identities and need an
  uninstall before installing a current APK. Before uninstalling, save your
  recovery key and confirm that your encrypted history can be restored.
- **Windows:** rerun the installer, or replace the complete portable directory.
- **Linux:** install the newer package using the same package manager. For a
  downloaded AppImage, replace the AppImage file. The direct-download Flatpak
  has no automatic SeND update repository; install the new bundle.
- **PWA:** choose **Reload app** when prompted. Finish uploads and recordings,
  and save unsent drafts before reloading.

For older clients sharing activity: both ends need build 109 or newer for
independent game/music/history slots, and build 110 or newer for persistent
Last.fm history and artwork.

## Media requirements

Android video compression is built in. Native desktop compression requires
`ffmpeg` and `ffprobe` on PATH. If preparation fails, choose **Retry
compression**, **Send original**, or **Cancel**. Original-quality uploads are
not automatic and can use much more data. Playback depends on the recipient's
codec support. PWA uploads keep the original video quality.

## Application data and recovery

SeND stores sessions and encryption state in the operating system's per-user
application-data and secure-storage locations. Never publish or casually copy
those directories; they can contain credentials and encryption keys.

If login persistence or encryption storage fails on Linux, check that a Secret
Service provider such as GNOME Keyring or KWallet is installed, unlocked and
available to your desktop session.

## Getting help

Check [known issues](KNOWN_ISSUES.md) first. Include your OS, desktop environment
or browser, SeND build, homeserver, whether the room is encrypted, and steps to
reproduce the problem.

Do not include access tokens, recovery keys, decrypted messages, encryption
keys or private media URLs in a report.
