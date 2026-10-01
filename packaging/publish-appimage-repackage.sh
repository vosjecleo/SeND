#!/usr/bin/env bash
# Publish only a verified replacement AppImage and its corresponding sources.
set -euo pipefail
release_id='0.9.36+112'
tag='v0.9.36-b112'
asset="SeND-$release_id-linux-appimage-x86_64.AppImage"
sources="SeND-$release_id-appimage-sources.tar.gz"
base="https://github.com/VosjeCleo/SeND/releases/download/$tag"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for name in SHA256SUMS "$asset" "$sources"; do
  curl -fLsS --retry 3 --connect-timeout 15 --max-time 900 \
    "$base/$name?repackage=$(date +%s)" -o "$work/$name"
done
test "$(wc -l < "$work/SHA256SUMS")" = 11
awk -v app="$asset" -v src="$sources" '$2 == app || $2 == src' "$work/SHA256SUMS" > "$work/repackage.sha256"
test "$(wc -l < "$work/repackage.sha256")" = 2
(cd "$work" && sha256sum -c repackage.sha256)
test "$(stat -c %s "$work/$asset")" -le $((160*1024*1024))
stage="/srv/storage/www/deltie/cord/.appimage-repackage-112-$(date +%s)"
ssh deltie "mkdir -m 0755 '$stage'"
scp -q "$work/$asset" "$work/$sources" "$work/SHA256SUMS" "$work/repackage.sha256" "deltie:$stage/"
ssh deltie bash -s -- "$stage" "$asset" "$sources" <<'REMOTE'
set -euo pipefail
stage="$1"; asset="$2"; sources="$3"
root='/srv/storage/www/deltie/cord'
test "$(jq -r .build "$root/releases.json")" = 112
(cd "$stage" && sha256sum -c repackage.sha256)
# Check every other published package checksum is unchanged before replacing.
awk -v app="$asset" -v src="$sources" '$2 != app && $2 != src' "$root/SHA256SUMS" | sort > "$stage/old-rest"
awk -v app="$asset" -v src="$sources" '$2 != app && $2 != src' "$stage/SHA256SUMS" | sort > "$stage/new-rest"
cmp "$stage/old-rest" "$stage/new-rest"
backup="/srv/storage/releases-archive/deltiecord/0.9.36-b112-appimage-before-$(date +%s)"
mkdir -p "$backup"
cp --reflink=auto "$root/$asset" "$root/SHA256SUMS" "$root/releases.json" "$backup/"
if [[ -f "$root/$sources" ]]; then
  cp --reflink=auto "$root/$sources" "$backup/"
fi
digest=$(sha256sum "$stage/$asset" | cut -d' ' -f1)
size=$(stat -c %s "$stage/$asset")
jq --arg name "$asset" --arg hash "$digest" --argjson size "$size" '
  (.. | objects | select(.name? == $name)) |= (.sha256 = $hash | .size = $size)
' "$root/releases.json" > "$stage/releases.json"
chmod 0644 "$stage/$asset" "$stage/$sources" "$stage/SHA256SUMS" "$stage/releases.json"
mv "$stage/$sources" "$root/$sources"
mv "$stage/$asset" "$root/$asset"
mv "$stage/SHA256SUMS" "$root/SHA256SUMS"
mv "$stage/releases.json" "$root/releases.json"
rm -- "$stage/repackage.sha256" "$stage/old-rest" "$stage/new-rest"
rmdir "$stage"
printf 'Replaced only AppImage; previous package and metadata retained in %s\n' "$backup"
REMOTE
curl -fLsS --connect-timeout 15 --max-time 60 \
  "https://deltie.net/SeND/releases.json?appimage-repackage=$(date +%s)" | \
  jq --arg name "$asset" '.. | objects | select(.name? == $name)'
