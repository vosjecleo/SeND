#!/usr/bin/env bash
# Add a verified Flatpak to the existing build, without touching other packages.
set -euo pipefail
export SEND_RELEASE_SIGNING_KEY_FILE="${SEND_RELEASE_SIGNING_KEY_FILE:-/home/cleo/.local/share/send-release-signing/ed25519-release-v1.pem}"
release_id=$(sed -n 's/^version: //p' pubspec.yaml)
[[ "$release_id" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]
tag="v${release_id/+/-b}"
asset="SeND-$release_id-linux-x86_64.flatpak"
sources="SeND-$release_id-flatpak-sources.flatpak"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for name in "$asset" "$sources" FLATPAK-SHA256SUMS FLATPAK-SHA256SUMS.sig; do
  curl -fLsS --retry 3 --connect-timeout 15 --max-time 900 \
    "https://github.com/VosjeCleo/SeND/releases/download/$tag/$name" -o "$work/$name"
done
python3 packaging/sign-release.py "$work/FLATPAK-SHA256SUMS" "$work/FLATPAK-SHA256SUMS.sig" --verify
test "$(wc -l < "$work/FLATPAK-SHA256SUMS")" = 2
expected=$(printf '%s\n' "$asset" "$sources" | sort)
test "$(awk '{print $2}' "$work/FLATPAK-SHA256SUMS" | sort)" = "$expected"
(cd "$work" && sha256sum -c FLATPAK-SHA256SUMS)
for name in releases.json releases.json.sig; do
  curl -fLsS --retry 3 --connect-timeout 15 --max-time 60 \
    "https://deltie.net/SeND/$name" -o "$work/$name"
done
python3 packaging/sign-release.py "$work/releases.json" "$work/releases.json.sig" --verify --manifest
before=$(sha256sum "$work/releases.json" | cut -d' ' -f1)
digest=$(sha256sum "$work/$asset" | cut -d' ' -f1)
size=$(stat -c %s "$work/$asset")
jq --arg name "$asset" --arg hash "$digest" --argjson size "$size" --arg release "$release_id" '
  def add_flatpak($channel):
    .platforms.linux[$channel] = (((.platforms.linux[$channel] // []) | map(select(.name != $name))) +
      [{name: $name, sha256: $hash, size: $size}]);
  add_flatpak("latest") |
  if ((.stable_version // "") + "+" + ((.stable_build // "") | tostring)) == $release then
    add_flatpak("stable")
  else . end
' "$work/releases.json" > "$work/releases.updated.json"
mv "$work/releases.updated.json" "$work/releases.json"
python3 packaging/sign-release.py "$work/releases.json" "$work/releases.json.sig" --manifest
python3 packaging/sign-release.py "$work/releases.json" "$work/releases.json.sig" --verify --manifest
stage="/srv/storage/www/deltie/cord/.flatpak-${release_id##*+}-$(date +%s)"
ssh deltie "mkdir -m 0755 '$stage'"
scp -q "$work/$asset" "$work/$sources" "$work/FLATPAK-SHA256SUMS" "$work/FLATPAK-SHA256SUMS.sig" "$work/releases.json" "$work/releases.json.sig" "deltie:$stage/"
ssh deltie bash -s -- "$stage" "$asset" "$sources" "$release_id" "$before" <<'REMOTE'
set -euo pipefail
stage="$1"; asset="$2"; sources="$3"; release_id="$4"
before="$5"
root='/srv/storage/www/deltie/cord'
test "$(sha256sum "$root/releases.json" | cut -d' ' -f1)" = "$before"
test "$(jq -r '.version + "+" + (.build|tostring)' "$root/releases.json")" = "$release_id"
(cd "$stage" && sha256sum -c FLATPAK-SHA256SUMS)
backup="/srv/storage/releases-archive/deltiecord/${release_id/+/-b}-flatpak-before-$(date +%s)"
mkdir -p "$backup"
cp "$root/releases.json" "$backup/"
cp "$root/releases.json.sig" "$backup/"
for name in "$asset" "$sources" FLATPAK-SHA256SUMS; do
  if [[ -f "$root/$name" ]]; then cp --reflink=auto "$root/$name" "$backup/"; fi
done
chmod 0644 "$stage/$asset" "$stage/$sources" "$stage/FLATPAK-SHA256SUMS" "$stage/FLATPAK-SHA256SUMS.sig" "$stage/releases.json" "$stage/releases.json.sig"
for name in "$asset" "$sources" FLATPAK-SHA256SUMS FLATPAK-SHA256SUMS.sig releases.json releases.json.sig; do
  mv "$stage/$name" "$root/$name"
done
for name in releases.json releases.json.sig; do
  target=release-metadata.json
  if [[ "$name" == *.sig ]]; then target=release-metadata.json.sig; fi
  install -m 0644 "$root/$name" "/srv/storage/www/deltiecord-web/current/.$target.new"
  mv "/srv/storage/www/deltiecord-web/current/.$target.new" "/srv/storage/www/deltiecord-web/current/$target"
done
rmdir "$stage"
printf 'Added Flatpak; previous metadata retained in %s\n' "$backup"
REMOTE
curl -fLsS "https://deltie.net/SeND/releases.json?flatpak=$(date +%s)" | \
  jq --arg name "$asset" '.. | objects | select(.name? == $name)'
