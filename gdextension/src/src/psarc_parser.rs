/// rs_net_ffi.rs — Pure-Rust PSARC/SNG parsing using santzit/Rocksmith2014.rs.
///
/// Uses `rocksmith2014-psarc` and `rocksmith2014-sng` Rust crates directly —
/// no .NET runtime, no NativeAOT shim, no CLR hosting required.

use std::fs::File;

pub use rocksmith2014_sng::Platform;

/// A parsed note extracted from the SNG arrangement.
#[derive(Clone, Debug)]
pub struct NoteEntry {
    pub time:         f32,
    pub fret:         i8,
    pub string_index: i8,
    pub sustain:      f32,
}

/// Parsed PSARC contents: notes from the lead (or highest-difficulty) arrangement
/// and raw WEM audio bytes for vgmstream playback.
pub struct PsarcData {
    pub notes:     Vec<NoteEntry>,
    pub wem_bytes: Option<Vec<u8>>,
}

impl PsarcData {
    /// Open and fully parse a `.psarc` file.
    ///
    /// 1. Finds the lead SNG arrangement (or any non-vocals SNG if no lead exists).
    /// 2. Decrypts and parses the SNG to extract notes from the highest difficulty level.
    /// 3. Extracts the first `.wem` audio file found in the archive.
    pub fn open(path: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let file = File::open(path)
            .map_err(|e| format!("Failed to open '{}': {}", path, e))?;

        let mut psarc = rocksmith2014_psarc::Psarc::read(file)
            .map_err(|e| format!("Failed to parse PSARC '{}': {}", path, e))?;

        let manifest = psarc.manifest().to_vec();

        // ── Find SNG arrangement ──────────────────────────────────────────────
        // Preference: lead > rhythm > bass > any non-vocals SNG
        let sng_name = manifest.iter()
            .filter(|n| n.ends_with(".sng") && !n.contains("vocals"))
            .max_by_key(|n| {
                if n.contains("lead")   { 3 }
                else if n.contains("rhythm") { 2 }
                else if n.contains("bass")   { 1 }
                else                         { 0 }
            })
            .cloned();

        let notes = if let Some(ref name) = sng_name {
            let encrypted = psarc.inflate_file(name)
                .map_err(|e| format!("Failed to inflate SNG '{}': {}", name, e))?;

            let sng = rocksmith2014_sng::Sng::from_encrypted(&encrypted, Platform::Pc)
                // Platform::Pc is correct for all official Rocksmith 2014 PC/Windows DLC.
                // Mac DLC uses Platform::Mac (different AES key) and is not supported here.
                .map_err(|e| format!("Failed to decrypt SNG '{}': {}", name, e))?;

            // Use the highest-difficulty level (most notes).
            let best_level = sng.levels.iter()
                .max_by_key(|lvl| lvl.notes.len());

            match best_level {
                Some(lvl) => lvl.notes.iter().map(|n| NoteEntry {
                    time:         n.time,
                    fret:         n.fret,
                    string_index: n.string_index,
                    sustain:      n.sustain,
                }).collect(),
                None => Vec::new(),
            }
        } else {
            Vec::new()
        };

        // ── Find WEM audio ────────────────────────────────────────────────────
        let wem_name = manifest.iter()
            .find(|n| n.ends_with(".wem"))
            .cloned();

        let wem_bytes = if let Some(ref name) = wem_name {
            Some(psarc.inflate_file(name)
                .map_err(|e| format!("Failed to inflate WEM '{}': {}", name, e))?)
        } else {
            None
        };

        Ok(PsarcData { notes, wem_bytes })
    }
}
