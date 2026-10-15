#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
# Keep this contract check tied to Flutter WebRTC's pinned Android dependency.
mapfile -t candidates < <(find "${GRADLE_USER_HOME:-$HOME/.gradle}/caches/modules-2/files-2.1/io.github.webrtc-sdk/android/150.7871.01" -name '*.aar' -type f)
[[ "${#candidates[@]}" -eq 1 ]] || { echo 'Expected the pinned Android WebRTC AAR.' >&2; exit 1; }
unzip -p "${candidates[0]}" classes.jar > "$work/webrtc.jar"
javac -d "$work/classes" \
  "$repo_root/android/app/src/main/java/net/deltie/deltiecord/RtcLogSecurity.java" \
  "$repo_root/tool/RtcLogSecurityTest.java"
java -cp "$work/classes:$work/webrtc.jar" net.deltie.deltiecord.RtcLogSecurityTest
