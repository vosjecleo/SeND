#!/usr/bin/env bash
# Re-select the verified latest web artifact already published on deltie.
# Run as cleo, not root. No nginx, certificate, DNS or service changes.
set -euo pipefail
IFS=$'\n\t'
if (( EUID == 0 )); then
  printf '%s\n' 'Run this script as cleo, without sudo.' >&2
  exit 1
fi
(( $# == 0 )) || { printf '%s\n' 'Usage: update-deltiecord.sh' >&2; exit 2; }
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$script_dir/deploy-web.py"
if [[ ! -f "$helper" ]]; then
  helper="$script_dir/deltiecord-update/deploy-web.py"
fi
[[ -f "$helper" ]] || { printf '%s\n' 'Missing deployment helper.' >&2; exit 1; }
for command in python3 jq sha256sum flock; do
  command -v "$command" >/dev/null
done
root='/srv/storage/www/deltiecord-web'
downloads='/srv/storage/www/deltie/cord'
[[ -d "$root" && -w "$root" ]]
exec 9>"$root/.update.lock"
flock -n 9 || { printf '%s\n' 'Another update is running.' >&2; exit 1; }
manifest="$(jq -ce '
  select(.release == "latest" or .release == "stable") |
  select((.platforms.web.latest | length) == 1) |
  {version, build, asset: .platforms.web.latest[0]}
' "$downloads/releases.json")"
version="$(jq -r '.version' <<<"$manifest")"
build="$(jq -r '.build' <<<"$manifest")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]]
release="$version+$build"
name="$(jq -r '.asset.name' <<<"$manifest")"
[[ "$name" == "SeND-${release}-web.tar.gz" || "$name" == "deltiecord-${release}-web.tar.gz" ]]
digest="$(jq -r '.asset.sha256' <<<"$manifest")"
[[ "$digest" =~ ^[0-9a-f]{64}$ ]]
archive="$downloads/$name"
[[ -f "$archive" && ! -L "$archive" ]]
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --strict
previous="$(readlink -- "$root/current" || true)"
python3 "$helper" "$archive" "$root" "$release"
printf 'Selected %s (previous: %s). No service restart needed.\n' "$release" "$previous"
