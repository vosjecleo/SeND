# Linux release packaging

Run `FLUTTER_BIN=/path/to/flutter packaging/build-release.sh` from the
repository root. GIF search uses Deltiecord's HTTPS proxy; the GIPHY key exists
only on that server and is never compiled into release binaries.
The script creates the Debian package, AppImage, checksums, and build metadata in
`dist/`. Generated artifacts and downloaded packaging tools are intentionally
ignored by Git.

Install the Debian package with `sudo apt install ./dist/deltiecord_0.9.0_amd64.deb`.
The package removes only application files when uninstalled; Matrix/session data
remains in the user's normal XDG application-data and Secret Service stores.

Run the AppImage with `chmod +x dist/Deltiecord-0.9.0-x86_64.AppImage` followed by
`./dist/Deltiecord-0.9.0-x86_64.AppImage`. A working desktop Secret Service is
required for persisted login and E2EE keys. Audio requires a reachable PulseAudio
or PipeWire-Pulse service. Wayland screen sharing requires PipeWire,
`xdg-desktop-portal`, and a working desktop portal backend such as
`xdg-desktop-portal-gtk` or `xdg-desktop-portal-kde`. The AppImage is assembled
with linuxdeploy; build it on the oldest supported Linux distribution for the
widest glibc compatibility.

The Arch recipe is in `packaging/arch/PKGBUILD` and intentionally builds from the
local checkout so it can be used for test packages before a public source release.
