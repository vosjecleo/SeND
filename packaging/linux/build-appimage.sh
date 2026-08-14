#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$repo_root/pubspec.yaml")"
tools_dir="$repo_root/packaging/.tools"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
appdir="$work/Deltiecord.AppDir"
linuxdeploy="$tools_dir/linuxdeploy-x86_64.AppImage"
plugin="$tools_dir/linuxdeploy-plugin-appimage-x86_64.AppImage"
mkdir -p "$tools_dir" "$repo_root/dist"

download() { test -x "$1" || { curl -fL --retry 3 "$2" -o "$1"; chmod +x "$1"; }; }
download "$linuxdeploy" "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
download "$plugin" "https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage"
"$repo_root/packaging/linux/build-appdir.sh" "$appdir"

export ARCH=x86_64
export VERSION="$version"
export OUTPUT="$repo_root/dist/Deltiecord-${version}-x86_64.AppImage"
export LDAI_OUTPUT="$OUTPUT"
export PATH="$tools_dir:$PATH"
export APPIMAGE_EXTRACT_AND_RUN=1
"$linuxdeploy" --appimage-extract-and-run \
  --appdir "$appdir" \
  --executable "$appdir/usr/lib/deltiecord/deltiecord" \
  --desktop-file "$appdir/usr/share/applications/net.deltie.deltiecord.desktop" \
  --icon-file "$appdir/usr/share/icons/hicolor/scalable/apps/net.deltie.deltiecord.svg" \
  --output appimage
test -x "$OUTPUT"
echo "$OUTPUT"
