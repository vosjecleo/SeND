#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
rust_toolchain=nightly-2026-09-23
tools_root="$PWD/.dart_tool/web-tools"
[[ "$("$tools_root/bin/wasm-bindgen" --version)" == 'wasm-bindgen 0.2.100' ]]
# Deliberately no shared memory/threads: this small worker module also runs
# without COOP/COEP and does not load Flutter or flutter_rust_bridge.
cargo "+$rust_toolchain" build --manifest-path tool/push-crypto/Cargo.toml \
  --locked --release --target wasm32-unknown-unknown
mkdir -p web/push-crypto
"$tools_root/bin/wasm-bindgen" tool/push-crypto/target/wasm32-unknown-unknown/release/send_push_crypto.wasm \
  --target no-modules --no-typescript --out-dir web/push-crypto --out-name send_push_crypto
