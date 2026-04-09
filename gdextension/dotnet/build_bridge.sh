#!/usr/bin/env bash
# build_bridge.sh — Build RocksmithBridge.dll (regular managed .NET, no NativeAOT).
#
# This script clones iminashi/Rocksmith2014.NET, then builds RocksmithBridge.dll
# as a regular managed class library.  The Rust GDExtension loads it at runtime
# via the .NET CLR hosting API (netcorehost / load_assembly_and_get_function_pointer).
#
# NO NativeAOT — no dotnet publish --aot, no ILCompiler, no shim DLL needed.
#
# Prerequisites (Linux x64):
#   dotnet SDK 9.0+   — https://dotnet.microsoft.com/download
#
# Usage:
#   cd gdextension/dotnet
#   bash build_bridge.sh
#
# Windows:
#   Run the same script in Git Bash or WSL.  Outputs are placed in
#   gdextension/bin/ and are identical cross-platform.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/deps"
BRIDGE_DIR="$SCRIPT_DIR/RocksmithBridge"
BIN_DIR="$SCRIPT_DIR/../bin"

# ── Clone Rocksmith2014.NET if not present ────────────────────────────────────
if [ ! -d "$DEPS_DIR/Rocksmith2014.NET" ]; then
    echo "[build_bridge] Cloning iminashi/Rocksmith2014.NET..."
    mkdir -p "$DEPS_DIR"
    git clone --depth 1 https://github.com/iminashi/Rocksmith2014.NET.git \
        "$DEPS_DIR/Rocksmith2014.NET"
    echo "[build_bridge] Clone complete."
else
    echo "[build_bridge] Rocksmith2014.NET already present — skipping clone."
fi

# ── Restore and build ─────────────────────────────────────────────────────────
echo "[build_bridge] Building RocksmithBridge.dll (regular managed .NET)..."
dotnet publish "$BRIDGE_DIR/RocksmithBridge.csproj" \
    -c Release \
    --output "$BRIDGE_DIR/publish" \
    --no-self-contained

# ── Copy output DLLs to gdextension/bin/ ─────────────────────────────────────
mkdir -p "$BIN_DIR"

# Core bridge DLL
cp "$BRIDGE_DIR/publish/RocksmithBridge.dll" "$BIN_DIR/"

# Rocksmith2014.NET managed DLLs
for dll in \
    Rocksmith2014.PSARC.dll \
    Rocksmith2014.SNG.dll \
    Rocksmith2014.Common.dll \
    ; do
    if [ -f "$BRIDGE_DIR/publish/$dll" ]; then
        cp "$BRIDGE_DIR/publish/$dll" "$BIN_DIR/"
        echo "[build_bridge] Copied $dll"
    fi
done

# F# runtime and any other required managed DLLs
for dll in \
    FSharp.Core.dll \
    FSharp.SystemTextJson.dll \
    Microsoft.IO.RecyclableMemoryStream.dll \
    Newtonsoft.Json.dll \
    Rocksmith2014.FSharpExtensions.dll \
    ; do
    if [ -f "$BRIDGE_DIR/publish/$dll" ]; then
        cp "$BRIDGE_DIR/publish/$dll" "$BIN_DIR/"
        echo "[build_bridge] Copied $dll"
    fi
done

# Runtime config (required by hostfxr CLR hosting to locate the .NET runtime)
# This file is committed to the repo so no build step is needed.  If you update
# the target framework, regenerate it by running this script.
if [ -f "$BRIDGE_DIR/publish/RocksmithBridge.runtimeconfig.json" ]; then
    cp "$BRIDGE_DIR/publish/RocksmithBridge.runtimeconfig.json" "$BIN_DIR/"
    echo "[build_bridge] Copied RocksmithBridge.runtimeconfig.json"
else
    # Class library builds don't produce a runtimeconfig.json — create one.
    cat > "$BIN_DIR/RocksmithBridge.runtimeconfig.json" <<'EOF'
{
  "runtimeOptions": {
    "tfm": "net10.0",
    "framework": {
      "name": "Microsoft.NETCore.App",
      "version": "10.0.0"
    }
  }
}
EOF
    echo "[build_bridge] Generated RocksmithBridge.runtimeconfig.json"
fi

echo "[build_bridge] Done — DLLs copied to $BIN_DIR"
ls -lh "$BIN_DIR"/*.dll "$BIN_DIR"/*.json 2>/dev/null || true
