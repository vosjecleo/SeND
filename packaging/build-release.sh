#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"
giphy_key_file="${GIPHY_API_KEY_FILE:-$repo_root/.secrets/giphy-api-key}"
test -s "$giphy_key_file" || {
  echo "Missing GIPHY key file: $giphy_key_file" >&2
  exit 1
}
giphy_api_key="$(tr -d '\r\n' <"$giphy_key_file")"
case "$giphy_api_key" in
  (*[!A-Za-z0-9_-]*|'') echo "The GIPHY key file has an invalid format." >&2; exit 1 ;;
esac
defines_file="$(mktemp)"
trap 'rm -f "$defines_file"' EXIT
chmod 600 "$defines_file"
printf '{"GIPHY_API_KEY":"%s"}\n' "$giphy_api_key" >"$defines_file"
cd "$repo_root"
rm -rf dist
mkdir -p dist
"$flutter_bin" build linux --release --dart-define-from-file="$defines_file"
packaging/linux/build-deb.sh
packaging/linux/build-appimage.sh
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
commit="$(git rev-parse HEAD)"
{
  echo "Deltiecord $version"
  echo "Git commit: $commit"
  echo "Built: $(date --iso-8601=seconds)"
  echo "Architecture: x86_64"
} >dist/BUILD-INFO.txt
(cd dist && sha256sum -- *.deb *.AppImage >SHA256SUMS)
