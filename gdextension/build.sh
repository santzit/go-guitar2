#!/usr/bin/env bash
# build.sh — Build the GoGuitar2 GDExtension for Linux and Windows.
#
# Usage:
#   cd gdextension && ./build.sh          # release (default)
#   cd gdextension && ./build.sh debug    # debug builds
#
# Prerequisites (Ubuntu / Debian):
#   sudo apt-get install -y g++-mingw-w64-x86-64
#   rustup target add x86_64-pc-windows-gnu

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROFILE="${1:-release}"
if [[ "$PROFILE" == "release" ]]; then
    CARGO_FLAGS="--release"
    LINUX_OUT="target/release/libgodot_goguitar_rs.so"
    WINDOWS_OUT="target/x86_64-pc-windows-gnu/release/godot_goguitar_rs.dll"
else
    CARGO_FLAGS=""
    LINUX_OUT="target/debug/libgodot_goguitar_rs.so"
    WINDOWS_OUT="target/x86_64-pc-windows-gnu/debug/godot_goguitar_rs.dll"
fi

# ── Linux ─────────────────────────────────────────────────────────────────────
echo "=== Building Linux x86_64 ($PROFILE) ==="
cargo build $CARGO_FLAGS
cp -v "$LINUX_OUT" bin/libgodot_goguitar_rs.so

# ── Windows (MinGW cross-compile) ─────────────────────────────────────────────
echo "=== Building Windows x86_64 ($PROFILE, MinGW cross-compile) ==="
rustup target add x86_64-pc-windows-gnu 2>/dev/null || true
cargo build $CARGO_FLAGS --target x86_64-pc-windows-gnu
cp -v "$WINDOWS_OUT" bin/godot_goguitar_rs.dll

echo ""
echo "=== Done ==="
echo "  bin/libgodot_goguitar_rs.so  (Linux)"
echo "  bin/godot_goguitar_rs.dll    (Windows)"
