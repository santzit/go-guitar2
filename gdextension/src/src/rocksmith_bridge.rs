use godot::prelude::*;
use crate::psarc_parser::PsarcData;

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
/// Uses pure-Rust PSARC + SNG parsing via [santzit/Rocksmith2014.rs](https://github.com/santzit/Rocksmith2014.rs).
/// No .NET runtime or external DLLs required.
///
/// GDScript usage:
/// ```gdscript
/// var bridge = RocksmithBridge.new()
/// if bridge.load_psarc("/absolute/path/to/song.psarc"):
///     var notes     = bridge.get_notes()        # Array[Dictionary]
///     var wem_bytes = bridge.get_wem_bytes()    # PackedByteArray (.wem Wwise audio)
/// ```
#[derive(GodotClass)]
#[class(base = Object)]
pub struct RocksmithBridge {
    #[base]
    base:       Base<Object>,
    notes:      Vec<NoteData>,
    wem_data:   Option<Vec<u8>>,   // WEM bytes (official DLC)
}

#[godot_api]
impl IObject for RocksmithBridge {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            notes:      Vec::new(),
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
        let data = PsarcData::open(path)?;

        // ── Notes from SNG ────────────────────────────────────────────────────
        self.notes = data.notes.iter()
            .filter(|n| (0..=24).contains(&n.fret) && (0..=5).contains(&n.string_index))
            .map(|n| NoteData {
                time:         n.time,
                fret:         n.fret as i32,
                string_index: n.string_index as i32,
                duration:     if n.sustain < 0.0 { 0.0 } else { n.sustain },
            })
            .collect();

        // Sort by time (SNG is already sorted, but be safe).
        self.notes.sort_by(|a, b| {
            a.time.partial_cmp(&b.time).unwrap_or(std::cmp::Ordering::Equal)
        });

        godot_print!(
            "RocksmithBridge: parsed {} notes via Rocksmith2014.rs",
            self.notes.len()
        );

        // ── WEM audio bytes ───────────────────────────────────────────────────
        if let Some(wem) = data.wem_bytes {
            godot_print!("RocksmithBridge: extracted {} WEM bytes", wem.len());
            self.wem_data = Some(wem);
        } else {
            godot_warn!("RocksmithBridge: no WEM audio found in PSARC.");
        }

        Ok(())
    }
}
