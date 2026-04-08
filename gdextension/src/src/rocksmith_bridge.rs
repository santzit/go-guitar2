use godot::prelude::*;
use crate::rs_net_ffi::PsarcHandle;

/// Internal representation of a single parsed note.
#[derive(Clone, Debug)]
struct NoteData {
    time:         f32,
    fret:         i32,
    string_index: i32,
    duration:     f32,
}

/// GDExtension class exposed to Godot as **RocksmithBridge**.
///
/// Wraps [iminashi/Rocksmith2014.NET](https://github.com/iminashi/Rocksmith2014.NET)
/// (PSARC + SNG parsing) via a C# NativeAOT shim and Rust FFI.
///
/// GDScript usage:
/// ```gdscript
/// var bridge = RocksmithBridge.new()
/// if bridge.load_psarc("/absolute/path/to/song.psarc"):
///     var notes     = bridge.get_notes()        # Array[Dictionary]
///     var wem_bytes = bridge.get_wem_bytes()    # PackedByteArray (.wem Wwise audio)
///     var ogg_bytes = bridge.get_audio_bytes()  # PackedByteArray (.ogg, CDLC only)
/// ```
#[derive(GodotClass)]
#[class(base = Object)]
pub struct RocksmithBridge {
    #[base]
    base:       Base<Object>,
    notes:      Vec<NoteData>,
    audio_data: Option<Vec<u8>>,   // OGG bytes (CDLC fallback)
    wem_data:   Option<Vec<u8>>,   // WEM bytes (official DLC)
}

#[godot_api]
impl IObject for RocksmithBridge {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            notes:      Vec::new(),
            audio_data: None,
            wem_data:   None,
        }
    }
}

#[godot_api]
impl RocksmithBridge {
    /// Open and parse a `.psarc` file at the given **absolute** path.
    /// Returns `true` on success.
    #[func]
    fn load_psarc(&mut self, path: GString) -> bool {
        self.notes.clear();
        self.audio_data = None;
        self.wem_data   = None;

        let path_str = path.to_string();
        godot_print!("RocksmithBridge: loading '{}'", path_str);

        match self.parse_psarc(&path_str) {
            Ok(_) => {
                godot_print!(
                    "RocksmithBridge: loaded {} notes from '{}'",
                    self.notes.len(),
                    path_str
                );
                true
            }
            Err(e) => {
                godot_error!("RocksmithBridge: failed to load '{}': {}", path_str, e);
                false
            }
        }
    }

    /// Returns an `Array[Dictionary]` where each entry has:
    /// `{ "time": float, "fret": int, "string": int, "duration": float }`
    #[func]
    fn get_notes(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for n in &self.notes {
            let mut dict: Dictionary<GString, Variant> = Dictionary::new();
            dict.set(&GString::from("time"),     n.time);
            dict.set(&GString::from("fret"),     n.fret);
            dict.set(&GString::from("string"),   n.string_index);
            dict.set(&GString::from("duration"), n.duration);
            arr.push(&dict.to_variant());
        }
        arr
    }

    /// Returns raw OGG audio bytes (CDLC only).
    #[func]
    fn get_audio_bytes(&self) -> PackedByteArray {
        match &self.audio_data {
            Some(data) => PackedByteArray::from(data.as_slice()),
            None       => PackedByteArray::new(),
        }
    }

    /// Returns raw WEM (Wwise) audio bytes from the official DLC.
    #[func]
    fn get_wem_bytes(&self) -> PackedByteArray {
        match &self.wem_data {
            Some(data) => PackedByteArray::from(data.as_slice()),
            None       => PackedByteArray::new(),
        }
    }
}

// ── Private implementation ────────────────────────────────────────────────────

impl RocksmithBridge {
    fn parse_psarc(&mut self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        // Open via the .NET NativeAOT shim (Rocksmith2014.NET PSARC + SNG).
        let handle = PsarcHandle::open(path)
            .ok_or_else(|| format!("RocksmithShim: rs_open_psarc failed for '{}'", path))?;

        // ── Notes (JSON array from the .NET SNG parser) ───────────────────
        if let Some(json) = handle.notes_json() {
            self.notes = parse_notes_json(&json);
            godot_print!(
                "RocksmithBridge: parsed {} notes via Rocksmith2014.NET",
                self.notes.len()
            );
        }

        // ── WEM audio bytes ───────────────────────────────────────────────
        if let Some(wem) = handle.wem_bytes() {
            godot_print!("RocksmithBridge: extracted {} WEM bytes", wem.len());
            self.wem_data = Some(wem);
        } else {
            godot_warn!("RocksmithBridge: no WEM audio found in PSARC.");
        }

        Ok(())
    }
}

// ── Minimal JSON notes parser ─────────────────────────────────────────────────

/// Parse the compact JSON produced by `Exports.cs BuildNotesJson()`.
/// Format: `[{"time":1.5,"fret":7,"string":3,"duration":0.12},...]`
///
/// We avoid a full JSON library dependency and instead use a hand-rolled
/// parser since the format is machine-generated and fully predictable.
fn parse_notes_json(json: &str) -> Vec<NoteData> {
    let mut notes = Vec::new();
    // Each object starts after "{" and ends before "}".
    for obj in json.split('{').skip(1) {
        let obj = obj.trim_end_matches(|c| c == ',' || c == ']').trim_end_matches('}');
        let time_val: f32   = obj.split(',').find_map(|p| parse_kv(p, "time"))    .unwrap_or(f32::NAN);
        let fret_val: i32   = obj.split(',').find_map(|p| parse_kv(p, "fret"))    .unwrap_or(-1);
        let string_val: i32 = obj.split(',').find_map(|p| parse_kv(p, "string"))  .unwrap_or(-1);
        let dur_val: f32    = obj.split(',').find_map(|p| parse_kv(p, "duration")).unwrap_or(f32::NAN);

        // Skip notes with missing or out-of-range fields.
        if time_val.is_nan() || time_val < 0.0 { continue; }
        if !(1..=24).contains(&fret_val) { continue; }
        if !(0..=5).contains(&string_val) { continue; }
        let duration = if dur_val.is_nan() || dur_val < 0.0 { 0.0 } else { dur_val };

        notes.push(NoteData { time: time_val, fret: fret_val, string_index: string_val, duration });
    }
    // Sort by time (the .NET library already sorts, but be safe).
    notes.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap_or(std::cmp::Ordering::Equal));
    notes
}

/// Extract the value for `key` from a single `"key":value` token.
fn parse_kv<T: std::str::FromStr>(pair: &str, key: &str) -> Option<T> {
    let mut kv = pair.splitn(2, ':');
    let k = kv.next()?.trim().trim_matches('"');
    if k != key { return None; }
    kv.next()?.trim().parse().ok()
}
