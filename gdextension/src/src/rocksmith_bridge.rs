use godot::prelude::*;

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
/// Wraps the [Rocksmith2014.rs](https://github.com/santzit/Rocksmith2014.rs)
/// library for opening `.psarc` archives and extracting note / audio data.
///
/// GDScript usage:
/// ```gdscript
/// var bridge = RocksmithBridge.new()
/// if bridge.load_psarc("/absolute/path/to/song.psarc"):
///     var notes = bridge.get_notes()          # Array[Dictionary]
///     var bytes = bridge.get_audio_bytes()    # PackedByteArray (OGG)
/// ```
#[derive(GodotClass)]
#[class(base = Object)]
pub struct RocksmithBridge {
    #[base]
    base:       Base<Object>,
    notes:      Vec<NoteData>,
    audio_data: Option<Vec<u8>>,
}

#[godot_api]
impl IObject for RocksmithBridge {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            notes:      Vec::new(),
            audio_data: None,
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

    /// Returns raw OGG audio bytes extracted from the `.psarc`.
    /// In GDScript convert with:
    /// `AudioStreamOggVorbis.load_from_buffer(bytes)`
    #[func]
    fn get_audio_bytes(&self) -> PackedByteArray {
        match &self.audio_data {
            Some(data) => PackedByteArray::from(data.as_slice()),
            None       => PackedByteArray::new(),
        }
    }
}

// ── Private implementation ────────────────────────────────────────────────────

impl RocksmithBridge {
    fn parse_psarc(&mut self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        use rocksmith2014_psarc::Psarc;
        use rocksmith2014_sng::Sng;
        use std::path::Path;

        let mut psarc = Psarc::open(Path::new(path))?;
        let manifest  = psarc.manifest().to_vec();

        // Determine the highest-difficulty arrangement available.
        // We prefer lead, then rhythm, then bass, then any .sng.
        let sng_name = manifest.iter()
            .find(|n| n.ends_with("_lead.sng"))
            .or_else(|| manifest.iter().find(|n| n.ends_with("_rhythm.sng")))
            .or_else(|| manifest.iter().find(|n| n.ends_with("_bass.sng")))
            .or_else(|| manifest.iter().find(|n| n.ends_with(".sng")))
            .cloned();

        if let Some(name) = sng_name {
            godot_print!("RocksmithBridge: parsing arrangement '{}'", name);
            let data = psarc.inflate_file(&name)?;
            let sng  = Sng::read(&data)?;

            // Use the highest-difficulty level (last in the levels list,
            // sorted by difficulty ascending by the Rocksmith format).
            let max_diff = sng.metadata.max_difficulty;
            let level = sng.levels.iter()
                .filter(|l| l.difficulty <= max_diff)
                .last()
                .or_else(|| sng.levels.last());

            if let Some(lvl) = level {
                for note in &lvl.notes {
                    // Skip chord-reference notes (chord_id != -1 means the note
                    // belongs to a chord event that is listed separately).
                    if note.chord_id == -1 {
                        self.notes.push(NoteData {
                            time:         note.time,
                            fret:         note.fret as i32,
                            string_index: note.string_index as i32,
                            duration:     note.sustain,
                        });
                    }
                }
            }
        }

        // Sort notes by hit-time for the GDScript scheduler.
        self.notes.sort_by(|a, b| {
            a.time.partial_cmp(&b.time).unwrap_or(std::cmp::Ordering::Equal)
        });

        // ── Audio: first .ogg found in the manifest ───────────────────────
        let ogg_name = manifest.iter()
            .find(|n| n.ends_with(".ogg"))
            .cloned();

        if let Some(name) = ogg_name {
            godot_print!("RocksmithBridge: extracting audio '{}'", name);
            match psarc.inflate_file(&name) {
                Ok(data) => { self.audio_data = Some(data); }
                Err(e)   => { godot_warn!("RocksmithBridge: audio extraction failed: {}", e); }
            }
        }

        Ok(())
    }
}
