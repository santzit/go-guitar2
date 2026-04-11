# Copilot Instructions — GoGuitar2

## Project Overview

A Rocksmith 2014-style guitar game built in **Godot 4.4.1** 

## Architecture

```
Godot 4.4.1 (GDScript)
  └─ Rust GDExtension  (libgodot_rocksmith.so / godot_rocksmith.dll)
       ├─ Pure-Rust PSARC/SNG parsing
       │    ├─ rocksmith2014-psarc   (Rust crate — PSARC extraction)
       │    └─ rocksmith2014-sng     (Rust crate — SNG note parsing + decryption)
       │         Source: https://github.com/santzit/Rocksmith2014.rs
       └─ vgmstream FFI               (WEM → PCM-16 audio, statically linked)
```
**Key principle:** 

- Use Godot Game Engine 4.4.1
- Use cpal for Audio DI (input)
- Use vgmstream for Wwise(.WEM) audio 
- Use Rust for GDExtension (Godot Extension)
- Use santzit/Rocksmith2014.rs Rust crates for PSARC + SNG parsing (NO .NET, NO CLR hosting)
- No .NET bridge, no RocksmithBridge.dll, no CLR hosting required


## Directory Layout

```
gdextension/
  bin/                        Pre-built binaries shipped with the game
    libgodot_rocksmith.so     Linux GDExtension
    godot_rocksmith.dll       Windows GDExtension
  lib/
    linux/libvgmstream.a      vgmstream static lib (Linux)
    windows/libvgmstream.a    vgmstream static lib (Windows, cross-compiled USE_VORBIS=ON)
    windows/libvorbis.a / libvorbisfile.a / libogg.a
  src/                        Rust GDExtension source
    src/
      lib.rs
      rocksmith_bridge.rs     GDExtension RocksmithBridge class
      rs_net_ffi.rs           Pure-Rust PSARC/SNG parsing via rocksmith2014-psarc + rocksmith2014-sng
      audio_engine.rs         GDExtension AudioEngine class (vgmstream WEM decode)
    build.rs                  Cargo build script (links vgmstream)
    Cargo.toml
  rocksmith_bridge.gdextension
scripts/
  music_play.gd               Main game scene script (requires DLC .psarc)
  music_play_demo.gd          Demo mode (no DLC required)
  rs_bridge.gd                GDScript wrapper for RocksmithBridge + AudioEngine
DLC/                          Place .psarc files here (gitignored)
```

## External repositories
If find any problem on the following libraries report reply comment and stop session. We will address the problem on repository.
- Rocksmith2014.rs
- gg-mixer
- cycfi/q

## Building

### Prerequisites

```bash
# Linux
sudo apt-get install -y build-essential curl git libvorbis-dev libogg-dev
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Cross-compile for Windows (optional)
sudo apt-get install -y mingw-w64 g++-mingw-w64-x86-64
```

### Build the Rust GDExtension

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

### Run the Game (Linux with xvfb)

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
  --scene scenes/music_play_demo.tscn &
# Screenshots are saved automatically to user://screenshots/
```

## Runtime Dependencies

### Linux
Only `libgodot_rocksmith.so` in `gdextension/bin/` is needed. No .NET runtime required.
System libraries used: `libvorbis`, `libogg` (standard system packages).

### Windows
Only `godot_rocksmith.dll` in `gdextension/bin/` is needed. No .NET runtime required.
All PSARC/SNG parsing is done in pure Rust — no external DLL dependencies.

## Key Coding Conventions

- **Rust** — GDExtension uses `godot-rust/gdext`. GDExtension classes use `#[derive(GodotClass)]`.
- **PSARC/SNG parsing** — pure Rust via `rocksmith2014-psarc` and `rocksmith2014-sng` crates from `santzit/Rocksmith2014.rs`. No .NET, no CLR hosting.
- **GDScript** — tabs for indentation. Type annotations required for non-obvious variables.
- **Screenshots** — the `music_play.gd` scene saves screenshots automatically every 5 s to
  `user://screenshots/`. After any code change, run the game and confirm screenshots look correct.

## Testing

After making changes, always:
1. Rebuild (`cargo build --release`) and copy `.so` to `gdextension/bin/`.
2. Run the game with `Xvfb` and verify the Output panel shows:
   - `RocksmithBridge: loading '...'`
   - `RocksmithBridge: parsed N notes via Rocksmith2014.rs`
   - `RsBridge: AudioEngine.open() returned: true`
3. Check the 5 auto-saved screenshots in `user://screenshots/`.

