#!/usr/bin/env bash
set -euo pipefail

rustup toolchain install 1.99.1 --profile minimal
rustup override set 1.99.1
rustup target add aarch64-linux-android
python tools/engine_updater.py stage
python tools/sync_native_pins.py
cargo test --locked --manifest-path native/artoffice_core/Cargo.toml

sdk="${ANDROID_HOME:?}"
bash tools/ci/install_android.sh 'ndk;28.2.13676358'
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS='-C link-arg=-Wl,-z,max-page-size=16384'
cargo build --locked --release --target aarch64-linux-android --manifest-path native/artoffice_core/Cargo.toml
python tools/collect_rust_licenses.py
git diff --exit-code -- native/artoffice_core/Cargo.toml native/artoffice_core/Cargo.lock
mkdir -p build/native-candidate
cp native/artoffice_core/target/aarch64-linux-android/release/libartoffice_core.so build/native-candidate/
cp assets/legal/rust-licenses.json build/native-candidate/
cp upstream/engines.lock.json build/native-candidate/
