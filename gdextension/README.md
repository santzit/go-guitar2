# GoGuitar GDExtension

Rust GDExtension that bridges Godot 4 to Rocksmith 2014 PSARC/SNG parsing and
Wwise WEM audio decoding. Uses pure-Rust crates from
[santzit/Rocksmith2014.rs](https://github.com/santzit/Rocksmith2014.rs) —
no .NET runtime, no external DLLs required.

---

## Prerequisites

| Tool | Version |
|------|---------|
| [Rust toolchain](https://rustup.rs) | stable ≥ 1.75 |
| [Godot Game Engine](https://github.com/godotengine/godot) | 4.4.1 |

---

## Build

```bash
cd gdextension
cargo build --release
```

Copy the compiled library to `bin/`:

```bash
# Linux
cp target/release/libgodot_goguitar_rs.so bin/

# Windows
cp target/release/godot_goguitar_rs.dll bin/
cp target/release/godot_goguitar_rs.dll ../bin/

# macOS
cp target/release/libgodot_goguitar_rs.dylib bin/
```

Then open the project in Godot 4.4. The `RocksmithBridge` class becomes
available in GDScript and is used automatically by `scripts/rs_bridge.gd`.

---

## API

| Method | Signature | Description |
|--------|-----------|-------------|
| `load_psarc` | `(path: String) -> bool` | Open and parse a `.psarc` file (absolute path) |
| `get_notes` | `() -> Array[Dictionary]` | Notes with keys `time`, `fret`, `string`, `duration` |
| `get_audio_bytes` | `() -> PackedByteArray` | Raw OGG audio bytes from the song |

---

## Testing with DLC files

Place (or symlink) any `.psarc` file into `res://DLC/`.  
`music_play.gd` scans that directory at start-up and loads the **first** file it
finds. The DLC folder already contains several CDLC files for testing:

| File | Artist | Song |
|------|--------|------|
| `The-Cure-_In-Between-Days-_v2_p.psarc` | The Cure | In Between Days |
| `The-Cure_A-Forest_v3_DD_p.psarc` | The Cure | A Forest |
| `Tom-Petty-and-the-Heartbreakers_Dont-Do-Me-Like-That_v2_p.psarc` | Tom Petty | Don't Do Me Like That |
| `Tom-Petty_Love-Is-A-Long-Road-Dell_v1_1_p.psarc` | Tom Petty | Love Is A Long Road |
| `Tom-Petty_Runnin'-Down-a-Dream_v2_DD_p.psarc` | Tom Petty | Runnin' Down a Dream |

If no `.psarc` can be loaded (e.g. the GDExtension binary is not built yet)
the game falls back to built-in demo notes so the highway is always populated.
