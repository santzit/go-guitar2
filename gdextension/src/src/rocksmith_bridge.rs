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
///     var notes    = bridge.get_notes()       # Array[Dictionary]
///     var wem_bytes = bridge.get_wem_bytes()  # PackedByteArray (.wem Wwise audio)
///     var ogg_bytes = bridge.get_audio_bytes() # PackedByteArray (.ogg, CDLC only)
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

    /// Returns raw OGG audio bytes extracted from the `.psarc` (CDLC only).
    /// In GDScript convert with:
    /// `AudioStreamOggVorbis.load_from_buffer(bytes)`
    #[func]
    fn get_audio_bytes(&self) -> PackedByteArray {
        match &self.audio_data {
            Some(data) => PackedByteArray::from(data.as_slice()),
            None       => PackedByteArray::new(),
        }
    }

    /// Returns raw WEM (Wwise) audio bytes extracted from the `.psarc`.
    /// Use with the `AudioEngine` GDExtension class to decode to PCM:
    /// ```gdscript
    /// var eng = AudioEngine.new()
    /// if eng.open(bridge.get_wem_bytes()):
    ///     var stream = AudioStreamWAV.new()
    ///     stream.format   = AudioStreamWAV.FORMAT_16_BITS
    ///     stream.stereo   = (eng.get_channels() == 2)
    ///     stream.mix_rate = eng.get_sample_rate()
    ///     stream.data     = eng.decode_all()
    /// ```
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
            // SNG files inside a PSARC are AES-256-CTR encrypted + zlib-compressed
            // on top of the PSARC block-level compression.  inflate_file() only
            // strips the PSARC layer; we must decrypt the SNG layer ourselves.
            // CDLC is always PC-keyed; official disc content may use Mac keys.
            let data = psarc.inflate_file(&name)?;
            let sng  = Sng::from_encrypted(&data, rocksmith2014_sng::Platform::Pc)
                .or_else(|_| Sng::from_encrypted(&data, rocksmith2014_sng::Platform::Mac))?;

            // Use the highest-difficulty level (last in the levels list,
            // sorted by difficulty ascending by the Rocksmith format).
            let max_diff = sng.metadata.max_difficulty;
            let level = sng.levels.iter()
                .filter(|l| l.difficulty <= max_diff)
                .last()
                .or_else(|| sng.levels.last());

            if let Some(lvl) = level {
                for note in &lvl.notes {
                    if note.chord_id == -1 {
                        // Individual note: use it directly.
                        self.notes.push(NoteData {
                            time:         note.time,
                            fret:         note.fret as i32,
                            string_index: note.string_index as i32,
                            duration:     note.sustain,
                        });
                    } else {
                        // Chord event: expand to one NoteData per played string.
                        // sng.chords[chord_id].frets[string] == -1 means string
                        // is not played in this chord; >= 0 means it is played.
                        let chord_idx = note.chord_id as usize;
                        if chord_idx < sng.chords.len() {
                            let chord = &sng.chords[chord_idx];
                            for (str_idx, &fret) in chord.frets.iter().enumerate() {
                                if fret >= 0 {
                                    self.notes.push(NoteData {
                                        time:         note.time,
                                        fret:         fret as i32,
                                        string_index: str_idx as i32,
                                        duration:     note.sustain,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        // Sort notes by hit-time for the GDScript scheduler.
        self.notes.sort_by(|a, b| {
            a.time.partial_cmp(&b.time).unwrap_or(std::cmp::Ordering::Equal)
        });

        // ── Audio: OGG (CDLC) or WEM (official DLC) ─────────────────────────
        let ogg_name = manifest.iter()
            .find(|n| n.ends_with(".ogg"))
            .cloned();

        if let Some(name) = ogg_name {
            godot_print!("RocksmithBridge: extracting OGG audio '{}'", name);
            match psarc.inflate_file(&name) {
                Ok(data) => { self.audio_data = Some(data); }
                Err(e)   => { godot_warn!("RocksmithBridge: OGG extraction failed: {}", e); }
            }
        }

        // Extract the first WEM file found (main backing track).
        // AudioEngine (Rust/vgmstream) is used by GDScript to decode this.
        let wem_name = manifest.iter()
            .find(|n| n.ends_with(".wem"))
            .cloned();

        if let Some(name) = wem_name {
            godot_print!("RocksmithBridge: extracting WEM audio '{}'", name);
            match psarc.inflate_file(&name) {
                Ok(data) => {
                    godot_print!(
                        "RocksmithBridge: extracted {} WEM bytes",
                        data.len()
                    );
                    self.wem_data = Some(data);
                }
                Err(e) => {
                    godot_warn!("RocksmithBridge: WEM extraction failed: {}", e);
                }
            }
        }

        if self.audio_data.is_none() && self.wem_data.is_none() {
            godot_warn!("RocksmithBridge: no audio file found in PSARC.");
        }

        Ok(())
    }
}
