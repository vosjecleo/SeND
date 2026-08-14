#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bundle="$repo_root/build/linux/x64/release/bundle"
appdir="${1:?usage: build-appdir.sh APPDIR}"

test -x "$bundle/deltiecord" || { echo "Run flutter build linux --release first." >&2; exit 1; }
rm -rf "$appdir"
install -d "$appdir/usr/lib/deltiecord" "$appdir/usr/bin" \
  "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/scalable/apps"
cp -a "$bundle/." "$appdir/usr/lib/deltiecord/"
ln -s ../lib/deltiecord/deltiecord "$appdir/usr/bin/deltiecord"
install -m 0644 "$repo_root/packaging/linux/net.deltie.deltiecord.desktop" \
  "$appdir/usr/share/applications/net.deltie.deltiecord.desktop"
install -m 0644 "$repo_root/packaging/linux/net.deltie.deltiecord.svg" \
  "$appdir/usr/share/icons/hicolor/scalable/apps/net.deltie.deltiecord.svg"
ln -s usr/share/applications/net.deltie.deltiecord.desktop "$appdir/net.deltie.deltiecord.desktop"
ln -s usr/share/icons/hicolor/scalable/apps/net.deltie.deltiecord.svg "$appdir/net.deltie.deltiecord.svg"
ln -s net.deltie.deltiecord.svg "$appdir/.DirIcon"
