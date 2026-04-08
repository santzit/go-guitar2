#!/usr/bin/env bash
# build_shim.sh — Build the RocksmithShim NativeAOT library.
#
# Clones iminashi/Rocksmith2014.NET and compiles the C# shim with NativeAOT,
# producing librocksmith_shim.so (Linux) ready for use by the Rust GDExtension.
#
# Prerequisites (Linux x64):
#   dotnet SDK 10.0+   — https://dotnet.microsoft.com/download
#
# Usage:
#   cd gdextension/dotnet
#   bash build_shim.sh
#
# Windows:
#   Run this script in WSL or Git Bash, then additionally run:
#     dotnet publish -c Release -r win-x64
#   from gdextension/dotnet/RocksmithShim/ on a Windows machine and copy
#   RocksmithShim.dll to gdextension/bin/.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/deps"
SHIM_DIR="$SCRIPT_DIR/RocksmithShim"
BIN_DIR="$SCRIPT_DIR/../bin"
LIB_DIR="$SCRIPT_DIR/../lib/linux"

# ── Clone Rocksmith2014.NET if not present ────────────────────────────────────
if [ ! -d "$DEPS_DIR/Rocksmith2014.NET" ]; then
    echo "[build_shim] Cloning iminashi/Rocksmith2014.NET..."
    mkdir -p "$DEPS_DIR"
    git clone --depth 1 https://github.com/iminashi/Rocksmith2014.NET \
        "$DEPS_DIR/Rocksmith2014.NET"
fi

# ── Build NativeAOT shared library ───────────────────────────────────────────
echo "[build_shim] Building NativeAOT shared library (linux-x64)..."
cd "$SHIM_DIR"
dotnet publish -c Release -r linux-x64

# ── Copy to bin/ and lib/ ─────────────────────────────────────────────────────
PUBLISH_DIR="$SHIM_DIR/bin/Release/net10.0/linux-x64/publish"
echo "[build_shim] Copying librocksmith_shim.so..."
mkdir -p "$BIN_DIR" "$LIB_DIR"
cp "$PUBLISH_DIR/RocksmithShim.so" "$BIN_DIR/librocksmith_shim.so"
cp "$PUBLISH_DIR/RocksmithShim.so" "$LIB_DIR/librocksmith_shim.so"

echo "[build_shim] Done: $BIN_DIR/librocksmith_shim.so"
ls -lh "$BIN_DIR/librocksmith_shim.so"
