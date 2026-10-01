#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$repo_root/pubspec.yaml")"
release_id="$(sed -n 's/^version: //p' "$repo_root/pubspec.yaml")"
tools_dir="$repo_root/packaging/.tools"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
appdir="$work/SeND.AppDir"
sources="$work/sources"
plugin="$tools_dir/linuxdeploy-plugin-appimage-x86_64.AppImage"
runtime="$tools_dir/appimage-runtime-x86_64"
mkdir -p "$tools_dir" "$repo_root/dist"

# Release tooling is pinned to immutable upstream tags and verified before it is
# ever made executable. Updating a tool requires reviewing the release and
# changing both its tag and checksum here.
plugin_url="https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/1-alpha-20250213-1/linuxdeploy-plugin-appimage-x86_64.AppImage"
plugin_sha256="992d502a248e14ab185448ddf6f6e7d25558cb84d4623c354c3af350c25fccb3"
runtime_url="https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64"
runtime_sha256="2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d"

ensure_tool() {
  local destination="$1" url="$2" expected="$3" temporary="${1}.download"
  if test -f "$destination" && echo "$expected  $destination" | sha256sum --check --status; then
    chmod 0755 "$destination"
    return
  fi
  rm -f "$temporary"
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$url" -o "$temporary"
  echo "$expected  $temporary" | sha256sum --check --status || {
    rm -f "$temporary"
    echo "Refusing unverified release tool: $url" >&2
    exit 1
  }
  chmod 0755 "$temporary"
  mv "$temporary" "$destination"
}

ensure_tool "$plugin" "$plugin_url" "$plugin_sha256"
ensure_tool "$runtime" "$runtime_url" "$runtime_sha256"
if [[ $# -ge 1 ]]; then
  # Repack already-built binaries; no Flutter compilation or version change.
  cp -a "$1" "$appdir"
  if [[ $# == 2 ]]; then
    cp -a "$2" "$sources"
  else
    mv "$appdir/usr/share/doc/deltiecord/mpv-runtime/sources" "$sources"
  fi
else
  "$repo_root/packaging/linux/build-appdir.sh" "$appdir"
  python3 "$repo_root/packaging/linux/bundle-mpv.py" "$appdir" "$sources"
fi
python3 "$repo_root/packaging/linux/bundle-application.py" "$appdir" "$sources"
source_asset="SeND-${release_id}-appimage-sources.tar.gz"
cp "$repo_root/packaging/linux/APPIMAGE-SOURCES.txt" "$sources/README.txt"
cp "$repo_root/packaging/linux/"bundle-*.py "$sources/"
mkdir -p "$sources/mpv-notices" "$sources/application-notices"
cp -a "$appdir/usr/share/doc/deltiecord/mpv-runtime/." "$sources/mpv-notices/"
cp -a "$appdir/usr/share/doc/deltiecord/application-runtime/." "$sources/application-notices/"
tar -C "$sources" -czf "$repo_root/dist/$source_asset" .
printf 'Corresponding dependency sources: %s\nhttps://github.com/VosjeCleo/SeND/releases/download/v%s-b%s/%s\n' \
  "$source_asset" "$version" "${release_id##*+}" "$source_asset" \
  >"$appdir/usr/share/doc/deltiecord/DEPENDENCY-SOURCES.txt"
printf 'appimage\n' >"$appdir/usr/lib/deltiecord/data/send-package"

export ARCH=x86_64
export VERSION="$version"
export OUTPUT="$repo_root/dist/SeND-${version}-x86_64.AppImage"
export LDAI_OUTPUT="$OUTPUT"
export LDAI_RUNTIME_FILE="$runtime"
export PATH="$tools_dir:$PATH"
export APPIMAGE_EXTRACT_AND_RUN=1
# mpv and its media dependencies are now bundled with private RUNPATHs. The host
# GTK, graphics drivers, libc and session stack deliberately remain untouched.
"$plugin" --appimage-extract-and-run --appdir "$appdir"
test -x "$OUTPUT"
# Source archives previously inflated this to 660 MiB. Fail before publication.
[[ "$(stat -c '%s' "$OUTPUT")" -le $((160 * 1024 * 1024)) ]] || {
  echo 'AppImage exceeds the 160 MiB runtime size budget' >&2
  exit 1
}
echo "$OUTPUT"
