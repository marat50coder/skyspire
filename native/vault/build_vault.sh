#!/usr/bin/env bash
# build_vault.sh — regenerate + rebuild libspire_vault.so for every Android
# ABI we ship, and drop the resulting .so files into
# android/app/src/main/jniLibs so the next Flutter build picks them up.
#
# Prerequisites:
#   • rustup default stable (or nightly, both tested)
#   • rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#   • cargo install cargo-ndk
#   • Android NDK installed — the script reads ANDROID_NDK_HOME, falling back
#     to $HOME/Library/Android/sdk/ndk/27.0.12077973 on macOS.
#
# Windows: run from WSL. Native PowerShell is not supported because
# cargo-ndk invokes POSIX-only Android build tools.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    if [[ -d "${HOME}/Library/Android/sdk/ndk/27.0.12077973" ]]; then
        export ANDROID_NDK_HOME="${HOME}/Library/Android/sdk/ndk/27.0.12077973"
    elif [[ -d "${HOME}/Android/Sdk/ndk/27.0.12077973" ]]; then
        export ANDROID_NDK_HOME="${HOME}/Android/Sdk/ndk/27.0.12077973"
    else
        echo "error: ANDROID_NDK_HOME not set and no fallback NDK found." >&2
        echo "       Install NDK 27 or export ANDROID_NDK_HOME manually." >&2
        exit 1
    fi
fi

echo ">> regenerating sealed.rs via vault_pack.py"
python3 "${HERE}/tools/vault_pack.py" > "${HERE}/src/sealed.rs"

echo ">> cargo ndk build (arm64-v8a, armeabi-v7a, x86_64)"
cd "${HERE}"
cargo ndk \
    -t arm64-v8a \
    -t armeabi-v7a \
    -t x86_64 \
    -o "${REPO}/android/app/src/main/jniLibs" \
    build --release

echo ">> emitted .so files:"
find "${REPO}/android/app/src/main/jniLibs" -name 'libspire_vault.so' -exec ls -l {} \;

echo
echo ">> done. commit the regenerated jniLibs/<abi>/libspire_vault.so files."
