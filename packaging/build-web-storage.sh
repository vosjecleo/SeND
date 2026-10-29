#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
target=web/sqlite3mc.wasm
checksum=62a34ec725631c0438e4255ce0c6059099bf8e7fb331e7d4d91a38e075f43a19
if ! [[ -s "$target" ]] || ! echo "$checksum  $target" | sha256sum --status --check; then
  curl --fail --location --retry 3 --output "$target.download" \
    https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.6.0/sqlite3mc.wasm
  echo "$checksum  $target.download" | sha256sum --status --check
  mv -- "$target.download" "$target"
fi
dart compile js tool/history_sql_worker.dart -O2 -o web/history_sql_worker.dart.js
cp -- assets/legal/sqlite-storage-licenses.txt web/sqlite-storage-licenses.txt
