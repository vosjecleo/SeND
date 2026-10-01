#!/usr/bin/env bash
# Add a verified Flatpak to the existing build, without touching other packages.
set -euo pipefail
release_id=$(sed -n 's/^version: //p' pubspec.yaml)
[[ "$release_id" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]
tag="v${release_id/+/-b}"
asset="SeND-$release_id-linux-x86_64.flatpak"
sources="SeND-$release_id-flatpak-sources.flatpak"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for name in "$asset" "$sources" FLATPAK-SHA256SUMS; do
  curl -fLsS --retry 3 --connect-timeout 15 --max-time 900 \
    "https://github.com/VosjeCleo/SeND/releases/download/$tag/$name" -o "$work/$name"
done
test "$(wc -l < "$work/FLATPAK-SHA256SUMS")" = 2
expected=$(printf '%s\n' "$asset" "$sources" | sort)
test "$(awk '{print $2}' "$work/FLATPAK-SHA256SUMS" | sort)" = "$expected"
(cd "$work" && sha256sum -c FLATPAK-SHA256SUMS)
stage="/srv/storage/www/deltie/cord/.flatpak-${release_id##*+}-$(date +%s)"
ssh deltie "mkdir -m 0755 '$stage'"
scp -q "$work/$asset" "$work/$sources" "$work/FLATPAK-SHA256SUMS" "deltie:$stage/"
ssh deltie bash -s -- "$stage" "$asset" "$sources" "$release_id" <<'REMOTE'
set -euo pipefail
stage="$1"; asset="$2"; sources="$3"; release_id="$4"
root='/srv/storage/www/deltie/cord'
test "$(jq -r '.version + "+" + (.build|tostring)' "$root/releases.json")" = "$release_id"
(cd "$stage" && sha256sum -c FLATPAK-SHA256SUMS)
backup="/srv/storage/releases-archive/deltiecord/${release_id/+/-b}-flatpak-before-$(date +%s)"
mkdir -p "$backup"
cp "$root/releases.json" "$backup/"
for name in "$asset" "$sources" FLATPAK-SHA256SUMS; do
  if [[ -f "$root/$name" ]]; then cp --reflink=auto "$root/$name" "$backup/"; fi
done
digest=$(sha256sum "$stage/$asset" | cut -d' ' -f1)
size=$(stat -c %s "$stage/$asset")
jq --arg name "$asset" --arg hash "$digest" --argjson size "$size" '
  .platforms.linux.latest = ((.platforms.linux.latest | map(select(.name != $name))) +
    [{name: $name, sha256: $hash, size: $size}])
' "$root/releases.json" > "$stage/releases.json"
chmod 0644 "$stage/$asset" "$stage/$sources" "$stage/FLATPAK-SHA256SUMS" "$stage/releases.json"
for name in "$asset" "$sources" FLATPAK-SHA256SUMS releases.json; do
  mv "$stage/$name" "$root/$name"
done
rmdir "$stage"
printf 'Added Flatpak; previous metadata retained in %s\n' "$backup"
REMOTE
curl -fLsS "https://deltie.net/SeND/releases.json?flatpak=$(date +%s)" | \
  jq --arg name "$asset" '.. | objects | select(.name? == $name)'
