# Copilot Instructions — GoGuitar2

## Project Overview

A Rocksmith 2014-style guitar game built in **Godot 4.4.1** using a **Rust GDExtension** for PSARC
and SNG parsing, plus WEM audio decoding via vgmstream.

## Architecture

```
Godot 4.4.1 (GDScript)
  └─ Rust GDExtension  (libgodot_rocksmith.so / godot_rocksmith.dll)
       ├─ Rocksmith2014 NativeAOT/shim
       │    └─ RocksmithBridge.dll    (regular managed .NET — PSARC + SNG parsing)
       │         ├─ Rocksmith2014.PSARC.dll   (F# — PSARC extraction)
       │         └─ Rocksmith2014.SNG.dll     (F# — SNG note parsing + decryption)
       └─ vgmstream FFI               (WEM → PCM-16 audio, statically linked)
```

**Key principle:** 

- Use Godot Game Engine 4.4.1
- Use vgmstream for Wwise(.WEM) audio 
- Use Rust for GDExtension (Godot Extension)
- Use Rocksmith2014.NET for Rocksmith parse .sparc files
- Use Rust cpal for Audio



## Directory Layout

```
gdextension/
  bin/                        Pre-built binaries shipped with the game
    libgodot_rocksmith.so     Linux GDExtension
    godot_rocksmith.dll       Windows GDExtension
    RocksmithBridge.dll       Managed .NET bridge (no NativeAOT)
    Rocksmith2014.PSARC.dll   F# PSARC library (copied from build)
    Rocksmith2014.SNG.dll     F# SNG library   (copied from build)
    FSharp.Core.dll           FSharp.Core runtime
  dotnet/
    RocksmithBridge/          C# bridge project (regular .NET, NOT NativeAOT)
      RocksmithBridge.csproj
      Exports.cs              [UnmanagedCallersOnly] methods called via CLR hosting
    build_bridge.sh           Build script — clones Rocksmith2014.NET + builds bridge
    deps/Rocksmith2014.NET/   Cloned source (gitignored)
  lib/
    linux/libvgmstream.a      vgmstream static lib (Linux)
    windows/libvgmstream.a    vgmstream static lib (Windows, cross-compiled USE_VORBIS=ON)
    windows/libvorbis.a / libvorbisfile.a / libogg.a
  src/                        Rust GDExtension source
    src/
      lib.rs
      rocksmith_bridge.rs     GDExtension RocksmithBridge class
      rs_net_ffi.rs           CLR hosting — loads RocksmithBridge.dll via netcorehost
      audio_engine.rs         GDExtension AudioEngine class (vgmstream WEM decode)
    build.rs                  Cargo build script (links vgmstream)
    Cargo.toml
  rocksmith_bridge.gdextension
scripts/
  music_play.gd               Main game scene script
  rs_bridge.gd                GDScript wrapper for RocksmithBridge + AudioEngine
DLC/                          Place .psarc files here (gitignored)
```

## Building

### Prerequisites

```bash
# Linux
sudo apt-get install -y build-essential curl git dotnet-sdk-9.0
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Cross-compile for Windows (optional)
sudo apt-get install -y mingw-w64
```

### 1. Build the .NET Bridge (no NativeAOT)

```bash
cd gdextension/dotnet
bash build_bridge.sh
# Outputs: gdextension/bin/RocksmithBridge.dll + Rocksmith2014.*.dll + FSharp.Core.dll
```

### 2. Build the Rust GDExtension

```bash
# Linux
cd gdextension/src
cargo build --release
cp target/release/libgodot_rocksmith.so ../bin/

# Windows (cross-compile from Linux)
rustup target add x86_64-pc-windows-gnu
cargo build --release --target x86_64-pc-windows-gnu
cp target/x86_64-pc-windows-gnu/release/godot_rocksmith.dll ../bin/
```

### 3. Run the Game (Linux with xvfb)

```bash
# Install display server and Godot 4.4.1
sudo apt-get install -y xvfb libgl1-mesa-dri libgles2-mesa mesa-vulkan-drivers
wget -q https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
unzip -q Godot_v4.4.1-stable_linux.x86_64.zip
chmod +x Godot_v4.4.1-stable_linux.x86_64

# Start virtual display and run the game
Xvfb :99 -screen 0 1280x720x24 &
DISPLAY=:99 ./Godot_v4.4.1-stable_linux.x86_64 \
  --path /path/to/go-guitar2 \
  --scene scenes/music_play.tscn &
# Screenshots are saved automatically to user://screenshots/
```

## Runtime Dependencies

### Linux
All required `.so` files must be in `gdextension/bin/`:
- `libgodot_rocksmith.so` — Rust GDExtension
- `RocksmithBridge.dll` — managed .NET bridge
- `Rocksmith2014.PSARC.dll`, `Rocksmith2014.SNG.dll`, `Rocksmith2014.Common.dll`
- `FSharp.Core.dll`, `FSharp.SystemTextJson.dll`
- The .NET runtime must be installed (`dotnet` ≥ 9.0)

### Windows
All `.dll` files must be in `gdextension/bin/`:
- `godot_rocksmith.dll` — Rust GDExtension
- `RocksmithBridge.dll` and the Rocksmith2014.NET managed DLLs
- The .NET runtime must be installed (download from https://dotnet.microsoft.com/download)

## Key Coding Conventions

- **Rust** — GDExtension uses `godot-rust/gdext`. GDExtension classes use `#[derive(GodotClass)]`.
- **C# bridge** — uses NativeAOT
- **GDScript** — tabs for indentation. Type annotations required for non-obvious variables.
- **Screenshots** — the `music_play.gd` scene saves screenshots automatically every 5 s to
  `user://screenshots/`. After any code change, run the game and confirm screenshots look correct.

## Testing

After making changes, always:
1. Rebuild the affected components (`build_bridge.sh` and/or `cargo build --release`).
2. Run the game with `Xvfb` and verify the Output panel shows:
   - `RocksmithBridge: loading '...'`
   - `RocksmithBridge: loaded N notes`
   - `RsBridge: AudioEngine.open() returned: true`
3. Check the 5 auto-saved screenshots in `user://screenshots/`.
