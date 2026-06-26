#!/usr/bin/env bash
# Builds QwenASR's forced aligner (qwen3-aligner-0.6b) as an iOS xcframework
# and stages it under Vendor/QwenAligner/ for the Xcode project to consume.
#
# Prerequisites:
#   - Xcode + command line tools
#   - rustup (install from https://rustup.rs)
#   - git
#
# Run from anywhere; resolves paths relative to this script.

set -euo pipefail

# Source ~/.cargo/env so rustup/cargo are on PATH even from non-interactive shells.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Source clone lives under Vendor/ as a normal git repo we commit (incl. our
# FFI additions that we may PR upstream). Build output goes to Frameworks/.
QWEN_DIR="$REPO_ROOT/Vendor/QwenASR"
FRAMEWORK_OUT="$REPO_ROOT/LyricEditor/Frameworks"
LIB_NAME="qwen_asr"             # cdylib/staticlib name → libqwen_asr.a
CRATE_NAME="qwen-asr"           # cargo package name (workspace member)
LIB_CRATE_DIR="crates/qwen-asr" # relative to QWEN_DIR
HEADER_NAME="qwen_asr.h"        # cbindgen output

IOS_TARGETS=(
    "aarch64-apple-ios"          # device
    "aarch64-apple-ios-sim"      # Apple Silicon simulator
    "x86_64-apple-ios"           # Intel simulator (still useful for CI)
)

log() { printf "\033[1;34m[build]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

# --- 1. Toolchain ----------------------------------------------------------
command -v rustup >/dev/null || die "rustup not found. Install from https://rustup.rs"
command -v cargo  >/dev/null || die "cargo not found."

log "Ensuring iOS targets are installed"
for t in "${IOS_TARGETS[@]}"; do
    rustup target add "$t"
done

# --- 2. Source -------------------------------------------------------------
mkdir -p "$(dirname "$QWEN_DIR")" "$FRAMEWORK_OUT"
if [ ! -d "$QWEN_DIR" ]; then
    log "Cloning QwenASR into $QWEN_DIR"
    git clone https://github.com/huanglizhuo/QwenASR "$QWEN_DIR"
else
    log "Using existing $QWEN_DIR"
fi

# --- 3. Build per target ---------------------------------------------------
cd "$QWEN_DIR"

for t in "${IOS_TARGETS[@]}"; do
    log "cargo build --release --target $t --features ios"
    cargo build --release --target "$t" --features ios
done

# --- 4. Generate C header via cbindgen ------------------------------------
if ! command -v cbindgen >/dev/null; then
    log "Installing cbindgen"
    cargo install cbindgen
fi
log "Generating $HEADER_NAME"
STAGED_HEADERS="$(mktemp -d)/include"
mkdir -p "$STAGED_HEADERS"
(cd "$QWEN_DIR/$LIB_CRATE_DIR" && cbindgen --crate "$CRATE_NAME" --lang c --output "$STAGED_HEADERS/$HEADER_NAME")

cat > "$STAGED_HEADERS/module.modulemap" <<EOF
module QwenAligner {
    header "$HEADER_NAME"
    link "qwen_asr"
    link framework "Accelerate"
    export *
}
EOF

# --- 5. Stage xcframework -------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DEVICE_LIB="$TMP/lib-device.a"
SIM_LIB="$TMP/lib-sim.a"

cp "$QWEN_DIR/target/aarch64-apple-ios/release/lib${LIB_NAME}.a" "$DEVICE_LIB"

# fat sim library: arm64-sim + x86_64-sim
lipo -create \
    "$QWEN_DIR/target/aarch64-apple-ios-sim/release/lib${LIB_NAME}.a" \
    "$QWEN_DIR/target/x86_64-apple-ios/release/lib${LIB_NAME}.a" \
    -output "$SIM_LIB"

rm -rf "$FRAMEWORK_OUT/QwenAligner.xcframework"

log "Packaging xcframework into $FRAMEWORK_OUT"
xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" -headers "$STAGED_HEADERS" \
    -library "$SIM_LIB"    -headers "$STAGED_HEADERS" \
    -output  "$FRAMEWORK_OUT/QwenAligner.xcframework"

log "Done."
log "Built: $FRAMEWORK_OUT/QwenAligner.xcframework"
