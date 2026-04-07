# Rocksmith GDExtension

Rust GDExtension that bridges Godot 4 to the
[Rocksmith2014.rs](https://github.com/santzit/Rocksmith2014.rs) library for
loading `.psarc` archives and parsing `.sng` note/chord data.

---

## Prerequisites

| Tool | Version |
|------|---------|
| [Rust toolchain](https://rustup.rs) | stable ≥ 1.75 |
| Godot 4.4 | – (headers fetched automatically by gdext) |

---

## Build

```bash
cd gdextension/src
cargo build --release
```

Copy the compiled library to `gdextension/bin/`:

```bash
# Linux
mkdir -p ../bin
cp target/release/libgodot_rocksmith.so ../bin/

# Windows
mkdir -p ../bin
cp target/release/godot_rocksmith.dll ../bin/

# macOS
mkdir -p ../bin
cp target/release/libgodot_rocksmith.dylib ../bin/
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
