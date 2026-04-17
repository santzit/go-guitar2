use godot::prelude::*;
use crate::rsapi::PsarcData;

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
/// bridge.set_difficulty(100.0)        # optional — 100.0 = Hard/100% (default)
/// if bridge.load_psarc("/absolute/path/to/song.psarc"):
///     var notes           = bridge.get_notes()              # Array[Dictionary]
///     var wem_bytes       = bridge.get_wem_bytes()          # PackedByteArray — full song (MAIN WEM)
///     var preview_bytes   = bridge.get_preview_wem_bytes()  # PackedByteArray — short preview (PREVIEW WEM)
/// ```
#[derive(GodotClass)]
#[class(base = Object)]
pub struct RocksmithBridge {
    #[base]
    base:             Base<Object>,
    notes:            Vec<NoteData>,
    wem_data:         Option<Vec<u8>>,   // MAIN WEM — full-length backing track
    preview_wem_data: Option<Vec<u8>>,   // PREVIEW WEM — short clip for song-list preview
    sng_start_time:   f32,   // SNG arrangement start time (seconds from WEM position 0)
    sng_difficulty:   i32,   // max phraseIteration hard-band level used for diagnostics
    sng_capo:         i8,    // raw capo_fret_id from SNG metadata.
                             // RS2014 has no capo feature; field is diagnostic only.
                             // -1 = unset/invalid, 0 = no capo, >0 = frets already physical/baked.
                             // Fret values are ALWAYS physical — no offset is ever applied.
    sng_tuning:       Vec<i16>, // per-string semitone offsets from standard tuning
    /// DDC difficulty band: 0=Easy, 1=Medium, 2=Hard/100% (default).
    /// Set via `set_difficulty(percent)` before calling `load_psarc`.
    difficulty_band:  usize,
}

#[godot_api]
impl IObject for RocksmithBridge {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            notes:            Vec::new(),
            wem_data:         None,
            preview_wem_data: None,
            sng_start_time:   0.0,
            sng_difficulty:   -1,
            sng_capo:         0,
            sng_tuning:       vec![],
            difficulty_band:  2,   // default: Hard / 100%
        }
    }
}

#[godot_api]
impl RocksmithBridge {
    /// Set the DDC difficulty level before loading a PSARC.
    ///
    /// `percent` maps to the three difficulty bands Rocksmith uses per phrase:
    ///   0–33   → Easy  (difficulty band 0)
    ///   34–66  → Medium (difficulty band 1)
    ///   67–100 → Hard / 100% (difficulty band 2, default)
    ///
    /// Call this before `load_psarc` / `load_psarc_abs`.
    /// If not called, the default is 100% (Hard).
    #[func]
    fn set_difficulty(&mut self, percent: f64) {
        self.difficulty_band = if percent <= 33.0 { 0 } else if percent <= 66.0 { 1 } else { 2 };
        godot_print!(
            "RocksmithBridge: difficulty set to {:.0}% → band {}",
            percent, self.difficulty_band
        );
    }

    /// Open and parse a `.psarc` file at the given **absolute** path.
    /// Returns `true` on success.
    #[func]
    fn load_psarc(&mut self, path: GString) -> bool {
        self.notes.clear();
        self.wem_data         = None;
        self.preview_wem_data = None;

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

    /// Returns the short PREVIEW WEM bytes used for song-list preview playback.
    /// Returns an empty array when no preview WEM was found in the archive.
    #[func]
    fn get_preview_wem_bytes(&self) -> PackedByteArray {
        match &self.preview_wem_data {
            Some(data) => PackedByteArray::from(data.as_slice()),
            None       => PackedByteArray::new(),
        }
    }

    /// Returns a Dictionary with SNG diagnostic fields:
    ///   `{ "start_time": float, "difficulty": int, "capo": int, "tuning": Array[int] }`
    /// - `start_time`: when the arrangement begins in the WEM audio (seconds from WEM t=0).
    ///   Note times in `get_notes()` are already absolute from WEM t=0, so no offset
    ///   needs to be applied — this value is purely for diagnostic logging.
    /// - `difficulty`: difficulty index of the selected level (== max_difficulty).
    /// - `capo`: raw capo_fret_id from SNG metadata.  RS2014 has no capo feature;
    ///   this is diagnostic only.  -1=unset, 0=no capo, >0=value present but frets
    ///   are already physical/baked.  Fret values in get_notes() are always physical;
    ///   no offset is applied regardless of this field.
    /// - `tuning`: per-string semitone offsets from standard E-A-D-G-B-e tuning.
    ///   Use these to compute correct note names for alternate-tuning songs.
    #[func]
    fn get_sng_info(&self) -> Dictionary<GString, Variant> {
        let mut dict: Dictionary<GString, Variant> = Dictionary::new();
        dict.set(&GString::from("start_time"), self.sng_start_time);
        dict.set(&GString::from("difficulty"),  self.sng_difficulty);
        dict.set(&GString::from("capo"),        self.sng_capo as i32);
        let mut tuning_arr: Array<Variant> = Array::new();
        for &t in &self.sng_tuning {
            tuning_arr.push(&Variant::from(t as i32));
        }
        dict.set(&GString::from("tuning"), &tuning_arr.to_variant());
        dict
    }
}

// ── Private implementation ────────────────────────────────────────────────────

impl RocksmithBridge {
    fn parse_psarc(&mut self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let data = PsarcData::open(path, self.difficulty_band)?;

        // ── SNG diagnostic metadata ───────────────────────────────────────────
        self.sng_start_time = data.sng_start_time;
        self.sng_difficulty = data.sng_difficulty;
        self.sng_capo       = data.sng_capo;
        self.sng_tuning     = data.sng_tuning;   // move — data.sng_tuning no longer needed

        let tuning_str: Vec<String> = self.sng_tuning.iter().map(|t| t.to_string()).collect();
        godot_print!(
            "RocksmithBridge: SNG difficulty={}  start_time={:.3}s  capo={}  tuning=[{}]",
            self.sng_difficulty,
            self.sng_start_time,
            self.sng_capo,
            tuning_str.join(", "),
        );

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
            godot_print!("RocksmithBridge: extracted {} main WEM bytes", wem.len());
            self.wem_data = Some(wem);
        } else {
            godot_warn!("RocksmithBridge: no MAIN WEM audio found in PSARC.");
        }

        if let Some(prev) = data.preview_wem_bytes {
            godot_print!("RocksmithBridge: extracted {} preview WEM bytes", prev.len());
            self.preview_wem_data = Some(prev);
        }

        Ok(())
    }
}
