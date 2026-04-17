/// psarc_parser.rs — Pure-Rust PSARC/SNG parsing using santzit/Rocksmith2014.rs.
///
/// Uses `rocksmith2014-psarc` and `rocksmith2014-sng` Rust crates directly —
/// no .NET runtime, no NativeAOT shim, no CLR hosting required.

use std::collections::HashMap;
use std::fs::File;

pub use rocksmith2014_sng::Platform;
use rocksmith2014_sng::NoteMask;

/// A parsed note extracted from the SNG arrangement.
#[derive(Clone, Debug)]
pub struct NoteEntry {
    pub time:         f32,
    pub fret:         i8,
    pub string_index: i8,
    pub sustain:      f32,
}

/// Parsed PSARC contents: notes from the lead (or highest-difficulty) arrangement,
/// the full-length MAIN WEM for gameplay, and the short PREVIEW WEM for the song list.
pub struct PsarcData {
    pub notes:             Vec<NoteEntry>,
    /// Full-length backing track (MAIN role) used in the gameplay scene.
    pub wem_bytes:         Option<Vec<u8>>,
    /// Short preview clip (PREVIEW role) used in the song-list scene.
    pub preview_wem_bytes: Option<Vec<u8>>,
    /// SNG arrangement start time (seconds from WEM position 0).
    /// Note times are already absolute from WEM position 0, so this is
    /// informational only — no offset needs to be applied during playback.
    pub sng_start_time:    f32,
    /// SNG difficulty index of the selected level (== metadata.max_difficulty).
    pub sng_difficulty:    i32,
    /// Capo fret used by the arrangement (0 = no capo, -1 = not set).
    /// SNG fret values are already physical (absolute) fret numbers — identical to
    /// what Rocksmith displays on screen.  This field is informational only; it tells
    /// the player where to place the physical capo before playing.
    pub sng_capo:          i8,
    /// Per-string tuning offsets in semitones from standard E-A-D-G-B-e tuning.
    /// An all-zero (or empty) vector means standard tuning.
    pub sng_tuning:        Vec<i16>,
}

impl PsarcData {
    /// Open and fully parse a `.psarc` file.
    ///
    /// 1. Finds the lead SNG arrangement (or any non-vocals SNG if no lead exists).
    /// 2. Decrypts and parses the SNG to extract notes from the highest difficulty level.
    /// 3. Parses every `.bnk` (Wwise SoundBank) to build a WEM-ID → role map
    ///    (MAIN vs PREVIEW).  Banks whose name contains `_preview` reference preview
    ///    WEM IDs; all other banks reference main WEM IDs.  MAIN takes priority when
    ///    the same ID appears in both.
    /// 4. Classifies every `.wem` entry using the role map and returns the largest
    ///    MAIN WEM as `wem_bytes` and the largest PREVIEW WEM as `preview_wem_bytes`.
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
                if n.contains("lead")        { 3 }
                else if n.contains("rhythm") { 2 }
                else if n.contains("bass")   { 1 }
                else                         { 0 }
            })
            .cloned();

        let (notes, sng_start_time, sng_difficulty, sng_capo, sng_tuning) = if let Some(ref name) = sng_name {
            let encrypted = psarc.inflate_file(name)
                .map_err(|e| format!("Failed to inflate SNG '{}': {}", name, e))?;

            let sng = rocksmith2014_sng::Sng::from_encrypted(&encrypted, Platform::Pc)
                // Platform::Pc is correct for all official Rocksmith 2014 PC/Windows DLC.
                // Mac DLC uses Platform::Mac (different AES key) and is not supported here.
                .map_err(|e| format!("Failed to decrypt SNG '{}': {}", name, e))?;

            let max_diff   = sng.metadata.max_difficulty;
            let start_time = sng.metadata.start_time;
            // capo_fret_id is diagnostic only — Rocksmith 2014 has no capo support.
            // The field is typically 0 or -1.  Frets in the SNG are physical (absolute).
            let capo       = sng.metadata.capo_fret_id;
            let tuning     = sng.metadata.tuning.clone();

            // Select the master/100% difficulty level.
            //
            // Strategy: prefer the level whose .difficulty index matches
            // metadata.max_difficulty (the authoritative 100% level marker).
            // Fall back to max-notes-count for CDLCs where the metadata field is
            // unreliable (sometimes off-by-one or unset).  Tie-break on difficulty
            // index for determinism.
            let total_levels = sng.levels.len();
            let best_level = sng.levels.iter()
                .find(|lvl| lvl.difficulty == max_diff)
                .or_else(|| {
                    sng.levels.iter().max_by(|a, b| {
                        a.notes.len().cmp(&b.notes.len())
                            .then_with(|| a.difficulty.cmp(&b.difficulty))
                    })
                });

            match best_level {
                Some(lvl) => {
                    let difficulty = lvl.difficulty;
                    let note_count = lvl.notes.len();
                    // Log level selection details for diagnostics.
                    eprintln!(
                        "rsapi: SNG levels={} selected_difficulty={} note_events={} max_difficulty_meta={}",
                        total_levels, difficulty, note_count, max_diff
                    );
                    let mut entries: Vec<NoteEntry> = Vec::new();
                    for n in &lvl.notes {
                        // Skip notes flagged as IGNORE — they are never scored or displayed.
                        // HIGH_DENSITY notes must NOT be skipped: they are genuine playable
                        // notes that Rocksmith's DDC removes at lower difficulties but that
                        // are required at the highest (master) difficulty level.
                        if n.mask.contains(NoteMask::IGNORE) {
                            continue;
                        }

                        // SNG frets are physical (absolute) fret numbers — identical to
                        // what is displayed on screen in Rocksmith.  The sng_to_xml reference
                        // conversion uses them as-is without any capo offset.
                        // capo_fret_id is stored in metadata for informational purposes only
                        // (it tells you where to place the physical capo on the guitar before
                        // playing).  We must NOT add it to fret values; for songs without a
                        // capo, capo_fret_id is often -1, and adding it would shift every fret
                        // down by one, producing wrong notes.

                        if n.chord_id >= 0 {
                            // Chord event: look up per-string frets from the global chord
                            // template.  The note's own fret/string fields are meaningless for
                            // chord events (chord_id takes precedence).
                            if let Some(chord) = sng.chords.get(n.chord_id as usize) {
                                for s in 0i8..6 {
                                    let raw_fret = chord.frets[s as usize];
                                    if raw_fret < 0 { continue; }   // -1 = string not played
                                    entries.push(NoteEntry {
                                        time:         n.time,
                                        fret:         raw_fret,
                                        string_index: s,
                                        sustain:      n.sustain,
                                    });
                                }
                            }
                        } else {
                            // Single note: use fret/string directly from the note record.
                            entries.push(NoteEntry {
                                time:         n.time,
                                fret:         n.fret,
                                string_index: n.string_index,
                                sustain:      n.sustain,
                            });
                        }
                    }
                    (entries, start_time, difficulty, capo, tuning)
                }
                None => {
                    eprintln!(
                        "rsapi: SNG levels={} — no level found, max_difficulty_meta={}",
                        total_levels, max_diff
                    );
                    (Vec::new(), start_time, max_diff, capo, tuning)
                }
            }
        } else {
            (Vec::new(), 0.0f32, -1i32, 0i8, vec![])
        };

        // ── Build WEM ID → role map from Wwise SoundBank (.bnk) files ─────────
        // Each BNK's DIDX section lists the WEM IDs it references.
        // Banks with `_preview` in their path/name are preview banks; others are main.
        // MAIN takes priority: if a WEM ID appears in both, it is treated as MAIN.
        let bnk_names: Vec<String> = manifest.iter()
            .filter(|n| n.ends_with(".bnk"))
            .cloned()
            .collect();

        let (main_bnks, preview_bnks): (Vec<_>, Vec<_>) = bnk_names
            .into_iter()
            .partition(|name| !name.to_ascii_lowercase().contains("_preview"));

        // true = MAIN, false = PREVIEW
        let mut wem_role: HashMap<u32, bool> = HashMap::new();

        // Insert MAIN roles first so they always win.
        for bnk_name in &main_bnks {
            if let Ok(data) = psarc.inflate_file(bnk_name) {
                for id in wem_ids_from_bnk(&data) {
                    wem_role.insert(id, true);
                }
            }
        }
        // Insert PREVIEW roles only for IDs not already marked MAIN.
        for bnk_name in &preview_bnks {
            if let Ok(data) = psarc.inflate_file(bnk_name) {
                for id in wem_ids_from_bnk(&data) {
                    wem_role.entry(id).or_insert(false);
                }
            }
        }

        let has_bnk_roles = !wem_role.is_empty();

        // ── Classify and extract WEM files ────────────────────────────────────
        // For each .wem entry: determine its role, then keep the largest per role.
        let wem_entries: Vec<String> = manifest.iter()
            .filter(|n| n.ends_with(".wem"))
            .cloned()
            .collect();

        let mut best_main:    Option<(usize, Vec<u8>)> = None;
        let mut best_preview: Option<(usize, Vec<u8>)> = None;

        for entry in &wem_entries {
            let bytes = match psarc.inflate_file(entry) {
                Ok(b)  => b,
                Err(_) => continue,
            };

            // Extract the numeric WEM ID from the filename (e.g. "Audio/Windows/12345678.wem").
            let stem = std::path::Path::new(entry.as_str())
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("");
            let wem_id: Option<u32> = stem.parse().ok();

            // Determine role: BNK map takes priority; fall back to filename heuristic.
            let is_main = if has_bnk_roles {
                wem_id
                    .and_then(|id| wem_role.get(&id).copied())
                    .unwrap_or(true)   // unknown IDs are assumed MAIN
            } else {
                !is_preview_wem_name(entry)
            };

            let size = bytes.len();
            if is_main {
                if best_main.as_ref().map_or(true, |(s, _)| size > *s) {
                    best_main = Some((size, bytes));
                }
            } else if best_preview.as_ref().map_or(true, |(s, _)| size > *s) {
                best_preview = Some((size, bytes));
            }
        }

        // If no dedicated MAIN WEM was found, fall back to using the preview WEM for
        // gameplay audio.  This handles CDLCs and DLCs that package a single WEM file
        // which the BNK classification marks as PREVIEW.
        let preview_wem_bytes = best_preview.map(|(_, b)| b);
        let wem_bytes = match best_main {
            Some((_, b)) => Some(b),
            None => preview_wem_bytes.clone(),  // use preview as MAIN fallback
        };

        Ok(PsarcData { notes, wem_bytes, preview_wem_bytes, sng_start_time, sng_difficulty, sng_capo, sng_tuning })
    }
}

// ── BNK helpers ──────────────────────────────────────────────────────────────

/// Extract all external WEM IDs listed in a Wwise SoundBank's DIDX section.
///
/// BNK format: a sequence of chunks `[tag: 4 B][size: u32 LE][data: size B]`.
/// The DIDX chunk contains 12-byte entries: `[wem_id: u32 LE][offset: u32 LE][len: u32 LE]`.
fn wem_ids_from_bnk(data: &[u8]) -> Vec<u32> {
    let mut ids  = Vec::new();
    let mut i    = 0usize;

    while i + 8 <= data.len() {
        let tag  = &data[i..i + 4];
        let size = u32::from_le_bytes(
            data[i + 4..i + 8].try_into().unwrap_or([0; 4])
        ) as usize;

        if tag == b"DIDX" {
            let mut j = i + 8;
            while j + 12 <= i + 8 + size {
                let wem_id = u32::from_le_bytes(
                    data[j..j + 4].try_into().unwrap_or([0; 4])
                );
                ids.push(wem_id);
                j += 12;
            }
            break;   // only one DIDX section per bank
        }

        if size == 0 { break; }  // guard against malformed banks with zero-size chunks
        i += 8 + size;
    }

    ids
}


fn is_preview_wem_name(name: &str) -> bool {
    name.contains("PREVIEW") 
}
