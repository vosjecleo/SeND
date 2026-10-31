#!/usr/bin/env bash
# Used by standalone packaging workflows before uploading public assets.
set -euo pipefail
commit="${1:?Expected a commit SHA}"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid validation commit.' >&2; exit 2; }
attempts="${SEND_VALIDATION_ATTEMPTS:-120}"
[[ "$attempts" =~ ^[1-9][0-9]*$ ]] && ((attempts <= 120)) || exit 2
for ((attempt=1; attempt<=attempts; attempt++)); do
  runs="$(gh run list --repo "${GITHUB_REPOSITORY:?}" --workflow validation.yml \
    --commit "$commit" --event push --limit 10 --json databaseId,headSha,status,conclusion)"
  result="$(jq -r --arg commit "$commit" '
    [.[] | select(.headSha == $commit)] | max_by(.databaseId) |
    if . == null or .status != "completed" then "pending"
    elif .conclusion == "success" then "success" else "failed" end' <<<"$runs")"
  case "$result" in
    success) exit 0 ;;
    failed) echo "Validation failed for $commit. Not publishing." >&2; exit 1 ;;
  esac
  if ((attempt < attempts)); then sleep 15; fi
done
echo "No successful validation for $commit. Not publishing." >&2
exit 1
