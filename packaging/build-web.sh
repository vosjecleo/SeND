#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# Match pubspec.lock's vodozemac 0.7.0 ABI. All executable tools are compiled
# from pinned Cargo registry sources with their lockfiles, not downloaded by
# wasm-pack's implicit binary installer.
source_commit=6c01eb68c183ba994a0b7089dc3fd6c7d2dd8c65
rust_toolchain=nightly-2026-09-23
bindgen_version=0.2.100
workspace="$PWD/.dart_tool/web-crypto"
tools_root="$PWD/.dart_tool/web-tools"
mkdir -p -- "$workspace" "$tools_root" web/pkg
if [[ ! -d "$workspace/source/.git" ]]; then
  git init -q "$workspace/source"
  git -C "$workspace/source" remote add origin https://github.com/famedly/dart-vodozemac.git
fi
git -C "$workspace/source" fetch -q --depth 1 origin "$source_commit"
git -C "$workspace/source" checkout -q --detach "$source_commit"
[[ "$(git -C "$workspace/source" rev-parse HEAD)" == "$source_commit" ]]
[[ -z "$(git -C "$workspace/source" status --porcelain)" ]]
rustup toolchain install "$rust_toolchain" --profile minimal --component rust-src --target wasm32-unknown-unknown
if [[ ! -x "$tools_root/bin/wasm-bindgen" ]] || \
   [[ "$("$tools_root/bin/wasm-bindgen" --version)" != "wasm-bindgen $bindgen_version" ]]; then
  cargo install wasm-bindgen-cli --version "$bindgen_version" --locked --root "$tools_root"
fi
RUSTFLAGS='-C target-feature=+atomics,+bulk-memory,+mutable-globals' \
  cargo "+$rust_toolchain" build --manifest-path "$workspace/source/rust/Cargo.toml" \
  --locked --release --target wasm32-unknown-unknown -Z build-std=std,panic_abort
"$tools_root/bin/wasm-bindgen" \
  "$workspace/source/rust/target/wasm32-unknown-unknown/release/vodozemac_bindings_dart.wasm" \
  --target no-modules --no-typescript --out-dir "$PWD/web/pkg" --out-name vodozemac_bindings_dart
flutter pub get --enforce-lockfile
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run
test -s build/web/pkg/vodozemac_bindings_dart_bg.wasm
test -s build/web/sw.js
test -s build/web/browser_bridge.js
release_id="$(sed -n 's/^version: \([^[:space:]]*\).*/\1/p' pubspec.yaml)"
[[ "$release_id" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]
mkdir -p dist
tar -czf "dist/deltiecord-${release_id}-web.tar.gz" -C build/web .
