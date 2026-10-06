# SeND Flatpak

SeND is available as a direct-download x86-64 Flatpak, not a Flathub listing.
It uses the application ID `net.deltie.deltiecord` for upgrade compatibility.

Unlike the AppImage, this uses the GNOME 50 runtime's GTK, icon loaders, FFmpeg,
audio libraries and graphics stack. Libass, libplacebo and libmpv are built
against its SDK from pinned sources. No Debian media-library closure is copied.
The corresponding source extension is published as a separate optional bundle.

## Install and launch

Download the bundle from the [SeND releases page](https://deltie.net/SeND).
Check its checksum against `FLATPAK-SHA256SUMS` before installing.
For build 119, run:

```sh
flatpak install --user ./SeND-0.9.37+119-linux-x86_64.flatpak
flatpak run net.deltie.deltiecord
```

Accept installation of the GNOME runtime from Flathub when prompted. The runtime
is an additional shared download; it is not included in the application bundle.
This direct bundle has no SeND update repository: install newer bundles manually.
`flatpak update` still
updates the runtime. The in-app updater falls back to the download page for this package.

## Sandbox boundaries

The package grants networking, display/GPU/camera devices, PulseAudio microphone
and playback, Downloads-folder access, desktop notifications, Secret Service
and MPRIS access. Other file selections use desktop portals. It does **not**
grant unrestricted home-directory, host-process, or session-bus access.

Host game/process detection, Steam-library discovery and Discord IPC bridging
are not integrated across the sandbox boundary in this first package. Use a
native package if those features are required. MPRIS permissions allow access
to host music players, but end-to-end desktop integrations, screen sharing and
camera calls still need user testing on each desktop/portal implementation.
The sandbox uses separate application storage: it does not migrate or read an
existing native installation's session automatically.

## Build and publish

```sh
flatpak-builder --user --install-deps-from=flathub --repo=repo --bundle-sources build net.deltie.deltiecord.yml
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo repo SeND.flatpak net.deltie.deltiecord
```

Run from this directory. Normal release publication triggers the Flatpak CI
stage automatically. The `[flatpak-only]` commit marker also allows an isolated
repackage without changing the application version. CI builds, checks native
dependencies, launches the installed app inside its final sandbox and publishes
only the new Flatpak assets. `bash packaging/publish-flatpak.sh` verifies and
adds them to the existing Deltie download mirror, retaining rollback metadata.
