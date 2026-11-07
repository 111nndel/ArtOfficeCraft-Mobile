#!/usr/bin/env bash
set -euo pipefail

target="${1:-aarch64-linux-android}"
case "$target" in
  aarch64-linux-android) clang=aarch64-linux-android24-clang ;;
  x86_64-linux-android) clang=x86_64-linux-android24-clang ;;
  *) echo "Unsupported Android Rust target: $target" >&2; exit 2 ;;
esac
rustup toolchain install 1.99.1 --profile minimal
rustup override set 1.99.1
rustup target add "$target"
python tools/engine_updater.py stage
python tools/sync_native_pins.py
cargo test --locked --manifest-path native/artoffice_core/Cargo.toml

sdk="${ANDROID_HOME:?}"
bash tools/ci/install_android.sh 'ndk;28.2.13676358'
variable="${target^^}"
variable="${variable//-/_}"
export "CARGO_TARGET_${variable}_LINKER=$sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/$clang"
export "CARGO_TARGET_${variable}_RUSTFLAGS=-C link-arg=-Wl,-z,max-page-size=16384"
cargo build --locked --release --target "$target" --manifest-path native/artoffice_core/Cargo.toml
python tools/collect_rust_licenses.py
git diff --exit-code -- native/artoffice_core/Cargo.toml native/artoffice_core/Cargo.lock
mkdir -p build/native-candidate
cp "native/artoffice_core/target/$target/release/libartoffice_core.so" build/native-candidate/
cp assets/legal/rust-licenses.json build/native-candidate/
cp upstream/engines.lock.json build/native-candidate/
